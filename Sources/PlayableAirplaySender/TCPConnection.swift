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
public enum TCPFailure: Error, Equatable {
    /// The host name could not be turned into an address.
    case hostCouldNotBeResolved(String)

    /// The socket could not be opened at all.
    case socketCouldNotBeOpened

    /// The receiver did not accept the connection.
    case connectionRefused(String)

    /// The connection was open and is not any more.
    case connectionClosed

    /// Nothing arrived within the time allowed.
    case timedOut
}

/**
 A plain TCP connection, opened to a receiver and read and written in whole
 messages.

 Blocking, with a timeout on both directions, because the sender runs on a
 thread of its own and a state machine is easier to follow than a callback for
 every byte. The platform difference is two imports and nothing else: everything
 here is POSIX, which is what makes one implementation serve macOS and Linux.
 */
public final class TCPConnection {
    private var handle: Int32 = -1

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

    /// Closes the socket, and does nothing where it is already closed.
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
     @throws `TCPFailure.connectionClosed` where the receiver hung up.
     */
    public func write(_ bytes: Data) throws {
        var sent = 0

        while sent < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                send(handle, buffer.baseAddress!.advanced(by: sent), bytes.count - sent, Self.sendFlags)
            }

            guard written > 0 else { throw TCPFailure.connectionClosed }
            sent += written
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
     @throws `TCPFailure.timedOut` where nothing arrived in time, or
     `TCPFailure.connectionClosed` where the receiver hung up.
     */
    public func read(maximum: Int = 16 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maximum)
        let count = recv(handle, &buffer, maximum, 0)

        if count > 0 { return Data(buffer[0..<count]) }
        if count == 0 { throw TCPFailure.connectionClosed }
        if errno == EAGAIN || errno == EWOULDBLOCK { throw TCPFailure.timedOut }

        throw TCPFailure.connectionClosed
    }

    // MARK: - Private

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
