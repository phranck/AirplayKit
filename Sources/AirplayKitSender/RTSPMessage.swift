//
//  RTSPMessage.swift
//  The requests a sender writes and the answers it reads back.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What can go wrong reading an answer off the wire.
package enum RTSPFailure: Error, Equatable {
    /// The bytes are not a status line followed by headers.
    case answerIsNotReadable

    /// The receiver answered with a status other than 200.
    case receiverAnswered(status: Int, reason: String, request: String)
}

/**
 One request to a receiver.

 AirPlay carries both RTSP methods and plain HTTP ones on the same connection,
 and the only difference between them is the word on the first line, so both are
 built here.

 @property method `SETUP`, `RECORD`, `POST` and the rest.
 @property uri What the request is about, which is an `rtsp://` address for
 session methods and a path for the pairing ones.
 @property headers Everything beyond the ones this builds itself.
 @property body The bytes under the headers, if any.
 */
package struct RTSPRequest {
    public let method: String
    public let uri: String
    public var headers: [(name: String, value: String)]
    public let body: Data

    public init(method: String,
                uri: String,
                headers: [(name: String, value: String)] = [],
                body: Data = Data()) {
        self.method = method
        self.uri = uri
        self.headers = headers
        self.body = body
    }

    /**
     The request as bytes.

     `Content-Length` is written here rather than by the caller, because a
     length that disagrees with the body is a fault no receiver recovers from.

     @param sequence The `CSeq` this request carries.
     @returns The request, headers and body together.
     */
    public func encoded(sequence: Int) -> Data {
        var text = "\(method) \(uri) RTSP/1.0\r\n"
        text += "CSeq: \(sequence)\r\n"

        for header in headers {
            text += "\(header.name): \(header.value)\r\n"
        }

        if !body.isEmpty {
            text += "Content-Length: \(body.count)\r\n"
        }

        text += "\r\n"

        return Data(text.utf8) + body
    }
}

/**
 One answer from a receiver.

 @property status The number from the status line.
 @property reason The words after it, which a receiver sometimes uses to say why.
 @property headers Every header, in the order they arrived.
 @property body The bytes under them.
 */
package struct RTSPResponse: Equatable {
    public let status: Int
    public let reason: String
    public let headers: [(name: String, value: String)]
    public let body: Data

    public static func == (left: RTSPResponse, right: RTSPResponse) -> Bool {
        left.status == right.status
            && left.reason == right.reason
            && left.body == right.body
            && left.headers.map(\.name) == right.headers.map(\.name)
            && left.headers.map(\.value) == right.headers.map(\.value)
    }

    /// The value of a header, found without regard to how it was capitalised.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /**
     Reads an answer from the front of whatever has arrived.

     Returns nothing rather than failing where the buffer does not yet hold the
     whole of one, because TCP delivers what it likes when it likes.

     @param bytes Everything received and not yet consumed.
     @returns The answer and how many bytes it used, or nil where it is not all
     there yet.
     @throws `RTSPFailure.answerIsNotReadable` where the bytes cannot be a
     message at all.
     */
    public static func read(from bytes: Data) throws -> (response: RTSPResponse, consumed: Int)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = bytes.range(of: separator) else { return nil }

        let headerBytes = bytes[bytes.startIndex..<headerEnd.lowerBound]
        guard let text = String(data: Data(headerBytes), encoding: .utf8) else {
            throw RTSPFailure.answerIsNotReadable
        }

        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw RTSPFailure.answerIsNotReadable }

        // "RTSP/1.0 200 OK", and a receiver answering a plain HTTP request says
        // HTTP/1.1 on the same line, which is read the same way.
        let statusParts = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            throw RTSPFailure.answerIsNotReadable
        }

        var headers: [(name: String, value: String)] = []
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers.append((name, value))
        }

        let bodyStart = headerEnd.upperBound
        let declared = headers.first { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
        let length = declared.flatMap { Int($0.value) } ?? 0

        // A length that is not a length at all. `limitedBy` is no limit against
        // a negative offset, because the limit lies the other way, so the index
        // comes back before the body starts and slicing it aborts the process.
        // Anything that can answer on the receiver's port reaches this before
        // pairing, whilst the connection is still in the clear.
        guard length >= 0 else { throw RTSPFailure.answerIsNotReadable }

        guard let bodyEnd = bytes.index(bodyStart, offsetBy: length, limitedBy: bytes.endIndex) else {
            return nil
        }

        let response = RTSPResponse(status: status,
                                    reason: statusParts.count > 2 ? statusParts[2] : "",
                                    headers: headers,
                                    body: Data(bytes[bodyStart..<bodyEnd]))

        return (response, bytes.distance(from: bytes.startIndex, to: bodyEnd))
    }
}
