//
//  TCPConnection.swift
//  One socket, the same way on both platforms.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// Glibc types the socket kinds as an enumeration and Darwin as a plain number,
// which is the one place the two headers differ here.
#if canImport(Glibc)
private let streamSocket = Int32(SOCK_STREAM.rawValue)
#else
private let streamSocket = SOCK_STREAM
#endif

/// What can go wrong on a socket, in words rather than in an error number.
package enum TCPFailure: Error, Equatable {
    /// The host name could not be turned into an address.
    case hostCouldNotBeResolved(String)

    /// The socket could not be opened at all.
    case socketCouldNotBeOpened

    /// The receiver did not accept the connection.
    case connectionRefused(String)

    /// The connection was open and is not any more, because the far end hung up.
    case connectionClosed

    /// Nothing moved within the time allowed.
    case timedOut

    /**
     This end shut the socket down, which is what ``TCPConnection/stop()`` does.

     Told apart from a hangup by remembering the call rather than by reading the
     error number, because the two give the same one. Without that, a session
     that was closed on purpose and one the receiver dropped are the same line
     in a log.
     */
    case connectionWasStopped

    /**
     Part of a message went out and the rest did not.

     The connection is finished, whatever ended the write. Half a frame is on
     the wire, the encrypted channel's counter has already moved past it, and
     nothing the far end reads afterwards will open, so a retry on this socket
     sends good bytes after bad ones. Every later call on it throws this again
     rather than pretending otherwise.

     `because` carries whichever of the three actually happened, since a
     half-written message is a consequence rather than a cause.
     */
    indirect case messageWasPartlySent(bytes: Int, of: Int, because: TCPFailure)
}

/**
 A plain TCP connection, opened to a receiver and read and written in whole
 messages.

 Blocking, with a timeout on both directions, because the sender runs on a
 thread of its own and a state machine is easier to follow than a callback for
 every byte. The platform difference is two imports and nothing else: everything
 here is POSIX, which is what makes one implementation serve macOS and Linux.
 */
package final class TCPConnection {
    private var handle: Int32 = -1

    /**
     What this end has done to the socket, and what that did to a message.

     Under a lock because ``stop()`` and ``close()`` run on a different thread
     from the one inside `send` or `recv`, which is the whole arrangement those
     two exist for. Held only around these two values and never across a
     syscall, or ``stop()`` would wait for the call it is meant to bring back.
     */
    private let state = NSLock()
    private var wasStopped = false
    private var messageLeftHalfSent: (bytes: Int, of: Int, because: TCPFailure)?

    /// The address the receiver answered on, which later requests name in their URI.
    public private(set) var localAddress: String = ""

    /// The receiver's own address, which is what anything else claiming to be it is checked against.
    public private(set) var peerAddress: String = ""

    /**
     Opens a connection.

     @param host The receiver's host name or address.
     @param port The port to reach it on.
     @param timeout How long to wait, both for the connection and for anything
     read on it afterwards.
     @throws A `TCPFailure` describing which step did not work.
     */
    public init(host: String, port: UInt16, timeout: TimeInterval = 10) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = streamSocket

        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &found) == 0, let first = found else {
            throw TCPFailure.hostCouldNotBeResolved(host)
        }
        defer { freeaddrinfo(found) }

        handle = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard handle >= 0 else { throw TCPFailure.socketCouldNotBeOpened }

        setTimeout(timeout, for: SO_RCVTIMEO)
        setTimeout(timeout, for: SO_SNDTIMEO)

        // A receiver that hangs up mid-write must not take the whole process
        // down with a signal, which is what a bare write to a closed socket
        // does by default.
        var on: Int32 = 1
        #if canImport(Darwin)
        setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif

        guard connect(handle, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 else {
            let reason = String(cString: strerror(errno))
            close()
            throw TCPFailure.connectionRefused(reason)
        }

        localAddress = Self.addressOfSocket(handle, peer: false)
        peerAddress = Self.addressOfSocket(handle, peer: true)
    }

    deinit {
        close()
    }

    /**
     Wakes whatever is blocked on this socket, without releasing the descriptor.

     The step before ``close()``, and the reason there are two. A thread parked
     in `send` or `recv` does not come out when the descriptor is closed: on
     neither platform does closing wake a blocked call. It comes out when the
     socket is shut down, with a read of nought or a write that fails.

     So the order is: shut down, wait for the thread to leave, then close.
     Closing first leaves another thread inside a syscall on a descriptor number
     that the next `open` in the process can be handed, and the write it was
     part way through then lands in somebody else's file. That is silent, and it
     is not a crash, so nothing reports it.

     Calling it twice is allowed, and it does nothing on a closed socket.
     */
    public func stop() {
        // Recorded before the shutdown, so the thread this is about to bring
        // back out of its syscall finds the answer already there.
        state.lock()
        wasStopped = true
        state.unlock()

        guard handle >= 0 else { return }

        shutdown(handle, Int32(SHUT_RDWR))
    }

    /**
     Closes the socket, and does nothing where it is already closed.

     Only once nothing is inside a call on it. ``stop()`` is what makes that
     true, and says why.
     */
    public func close() {
        guard handle >= 0 else { return }

        #if canImport(Glibc)
        Glibc.close(handle)
        #else
        Darwin.close(handle)
        #endif

        handle = -1
    }

    /**
     Writes everything, however many times the kernel takes only part of it.

     @param bytes What to send.
     @throws `TCPFailure.connectionClosed` where the far end hung up,
     `TCPFailure.timedOut` where the send ran out of time,
     `TCPFailure.connectionWasStopped` where this end shut the socket down, or
     `TCPFailure.messageWasPartlySent` where any of those happened after some of
     the message had already gone, which ends the connection.
     */
    public func write(_ bytes: Data) throws {
        try refuseIfHalfAMessageWentOut()

        var sent = 0

        while sent < bytes.count {
            // The error number is taken inside the same closure as the call,
            // because anything at all in between can replace it.
            let outcome = bytes.withUnsafeBytes { buffer -> (written: Int, code: Int32) in
                let written = send(handle,
                                   buffer.baseAddress!.advanced(by: sent),
                                   bytes.count - sent,
                                   Self.sendFlags)

                return (written, errno)
            }

            guard outcome.written > 0 else {
                throw failure(afterSending: sent, of: bytes.count, code: outcome.code)
            }

            sent += outcome.written
        }
    }

    /**
     What keeps a write to a hung-up socket from ending the process.

     A bare write to a socket whose peer has closed raises SIGPIPE, and the
     default action for that signal is to terminate. The two platforms turn it
     off in different places: Darwin has the `SO_NOSIGPIPE` socket option, which
     is set once when the socket is opened, and Linux has none, so every send
     has to carry `MSG_NOSIGNAL` instead.

     Without this a receiver that goes away mid-stream takes the whole
     application down on Linux and merely fails on macOS, which is exactly the
     kind of difference that is never seen until it is somebody else's machine.
     */
    private static var sendFlags: Int32 {
        #if canImport(Glibc)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }

    /**
     Reads whatever has arrived, waiting for at least one byte.

     @param maximum The most to take in one go.
     @returns The bytes read, never empty.
     @throws `TCPFailure.timedOut` where nothing arrived in time,
     `TCPFailure.connectionWasStopped` where this end shut the socket down,
     `TCPFailure.connectionClosed` where the far end hung up, or
     `TCPFailure.messageWasPartlySent` where a write already left half a message
     on this socket, after which nothing read from it means anything.
     */
    public func read(maximum: Int = 16 * 1024) throws -> Data {
        try refuseIfHalfAMessageWentOut()

        var buffer = [UInt8](repeating: 0, count: maximum)
        let count = recv(handle, &buffer, maximum, 0)
        let code = errno

        if count > 0 { return Data(buffer[0..<count]) }

        // Nothing partial to report: a read either brought bytes or it did not,
        // so this only has to say which of the three ended it.
        throw failure(afterSending: 0, of: 0, code: code)
    }

    // MARK: - Private

    /**
     Which of the three things that end a call actually happened.

     @param sent How much of the message had already gone. Nought for a read,
     and for a write that failed on its first attempt.
     @param total How long the whole message is.
     @param code The error number the call left behind.
     */
    private func failure(afterSending sent: Int, of total: Int, code: Int32) -> TCPFailure {
        state.lock()
        let stopped = wasStopped
        state.unlock()

        // A shutdown here and a hangup at the far end leave the same number, so
        // the one this end did is told by remembering that it did it.
        let cause: TCPFailure
        if stopped {
            cause = .connectionWasStopped
        }
        else if code == EAGAIN || code == EWOULDBLOCK {
            cause = .timedOut
        }
        else {
            cause = .connectionClosed
        }

        guard sent > 0 else { return cause }

        let partial = (bytes: sent, of: total, because: cause)

        state.lock()
        messageLeftHalfSent = partial
        state.unlock()

        return .messageWasPartlySent(bytes: partial.bytes, of: partial.of, because: partial.because)
    }

    /// Refuses anything on a connection that already has half a message on the wire.
    private func refuseIfHalfAMessageWentOut() throws {
        state.lock()
        let partial = messageLeftHalfSent
        state.unlock()

        guard let partial else { return }

        throw TCPFailure.messageWasPartlySent(bytes: partial.bytes,
                                              of: partial.of,
                                              because: partial.because)
    }

    private func setTimeout(_ seconds: TimeInterval, for option: Int32) {
        var value = timeval(tv_sec: Int(seconds),
                            tv_usec: Self.microseconds(seconds))
        setsockopt(handle, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    #if canImport(Glibc)
    private static func microseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds - Double(Int(seconds))) * 1_000_000)
    }
    #else
    private static func microseconds(_ seconds: TimeInterval) -> Int32 {
        Int32((seconds - Double(Int(seconds))) * 1_000_000)
    }
    #endif

    /**
     One end of the socket as text.

     @param handle The socket.
     @param peer Whether to ask for the far end rather than this one.
     @returns The address, or an empty string where the socket cannot say.
     */
    private static func addressOfSocket(_ handle: Int32, peer: Bool) -> String {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)

        let found = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                (peer ? getpeername(handle, address, &length) : getsockname(handle, address, &length)) == 0
            }
        }
        guard found else { return "" }

        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let converted = withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { address in
                var addr = address.pointee.sin_addr
                return inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil
            }
        }

        return converted ? String(cString: text) : ""
    }
}
