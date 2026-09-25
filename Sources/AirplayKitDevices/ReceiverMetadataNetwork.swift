//
//  ReceiverMetadataNetwork.swift
//  Find standard UPnP descriptions for AirPlay receivers.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

package actor ReceiverMetadataResolver {
    package static let shared = ReceiverMetadataResolver()

    private var scanTask: Task<[String: URL], Never>?
    private var scanStarted: Date = .distantPast

    package func productName(host: String, manufacturer: String, model: String) async -> String {
        let fallback = DeviceAppearance.productName(manufacturer: manufacturer, model: model)
        guard !host.isEmpty else { return fallback }

        // The plain AirPlay endpoint is useful where only RAOP's short model has
        // reached Bonjour. It can run while the single SSDP search is in flight.
        async let airPlayInfo = Self.fetch(Self.infoURL(for: host))

        let locations = await descriptionLocations()
        let addresses = Self.ipv4Addresses(for: host)
        let location = addresses.compactMap { locations[$0] }.first
        let upnp = location == nil ? nil : await Self.fetch(location)

        return ReceiverMetadata.preferredName(upnp: upnp, airPlayInfo: await airPlayInfo,
                                              manufacturer: manufacturer, model: model)
    }

    private func descriptionLocations() async -> [String: URL] {
        if scanTask == nil || Date().timeIntervalSince(scanStarted) > 30 {
            scanStarted = Date()
            scanTask = Task.detached(priority: .utility) { Self.scanSSDP() }
        }
        return await scanTask?.value ?? [:]
    }

    private nonisolated static func infoURL(for host: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = 7000
        parts.path = "/info"
        return parts.url
    }

    private nonisolated static func fetch(_ url: URL?) async -> Data? {
        guard let url, url.scheme == "http" else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 3)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral,
                                 delegate: ReceiverMetadataNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 262_144 else { return nil }
        return data
    }

    private nonisolated static func scanSSDP() -> [String: URL] {
        #if canImport(Darwin)
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        #else
        let descriptor = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { return [:] }
        defer { _ = close(descriptor) }

        var destination = sockaddr_in()
        #if canImport(Darwin)
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(1900).bigEndian
        guard "239.255.255.250".withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1
        else { return [:] }

        let request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
                    + "MAN: \"ssdp:discover\"\r\nMX: 1\r\nST: upnp:rootdevice\r\n\r\n"
        let sent = request.withCString { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, bytes, strlen(bytes), 0, $0,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return [:] }

        var found: [String: URL] = [:]
        let deadline = Date().addingTimeInterval(1.8)
        while true {
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1_000))
            if remaining == 0 { break }
            var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&watched, 1, remaining) > 0, watched.revents & Int16(POLLIN) != 0
            else { break }
            if let (address, location) = receiveLocation(on: descriptor) { found[address] = location }
        }
        return found
    }

    private nonisolated static func receiveLocation(on descriptor: Int32) -> (String, URL)? {
        var packet = [UInt8](repeating: 0, count: 8_192)
        var source = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let length = packet.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, $0, &sourceLength)
                }
            }
        }
        guard length > 0, source.sin_family == sa_family_t(AF_INET) else { return nil }
        var address = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let printed = withUnsafePointer(to: &source.sin_addr) {
            inet_ntop(AF_INET, $0, &address, socklen_t(address.count))
        }
        guard printed != nil else { return nil }
        let sourceAddress = String(cString: address)
        guard let location = ReceiverMetadata.location(in: Data(packet.prefix(Int(length))),
                                                       from: sourceAddress) else { return nil }
        return (sourceAddress, location)
    }

    private nonisolated static func ipv4Addresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = {
            #if canImport(Darwin)
            return SOCK_STREAM
            #else
            return Int32(SOCK_STREAM.rawValue)
            #endif
        }()
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &first) == 0, let first else { return [] }
        defer { freeaddrinfo(first) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if entry.pointee.ai_family == AF_INET, let socketAddress = entry.pointee.ai_addr {
                let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr
                }
                var printed = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addressCopy = address
                if inet_ntop(AF_INET, &addressCopy, &printed,
                             socklen_t(printed.count)) != nil {
                    addresses.append(String(cString: printed))
                }
            }
            cursor = entry.pointee.ai_next
        }
        return addresses
    }
}

private final class ReceiverMetadataNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
