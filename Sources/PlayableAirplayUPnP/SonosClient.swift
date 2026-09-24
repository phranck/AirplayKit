//
//  SonosClient.swift
//  Asking a speaker directly, over the services it offers on port 1400.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A speaker, asked through its own services rather than through AirPlay.
///
/// A Sonos gives nothing away over AirPlay. It advertises the same status value
/// whatever it is doing, and its `/info` carries no volume and no state, so
/// everything ``AirPlayReceiver`` reports about an Apple receiver is false for
/// it in the sense of never moving. It publishes the same facts over its own
/// UPnP services instead, on port 1400, without authentication.
///
/// ```swift
/// let speaker = SonosClient(host: "Sonos-38420B60C6CE.local")
/// let playing = try await speaker.playback()
/// print(playing.state, playing.volume)
/// ```
///
/// The host comes from an ordinary AirPlay browse: a Sonos publishes its
/// service under a name of that shape, and the same host answers on 1400.
///
/// **Only Sonos.** Port 1400 and these services are theirs. A receiver from
/// anybody else answers nothing there, and the failure looks like a speaker
/// that is switched off.
public struct SonosClient: Sendable {
    /// Where to reach it, as a host name rather than an address.
    public let host: String

    /// The port its own services listen on. 1400 on every speaker measured.
    public let port: Int

    /// How long to wait for an answer before giving up.
    ///
    /// A speaker on the same network answers in a few milliseconds, so a wait
    /// this long means it is asleep or gone rather than busy.
    public let timeout: TimeInterval

    private let session: URLSession

    /// Points at one speaker. Nothing is asked until something is asked for.
    ///
    /// - Parameters:
    ///   - host: Its host name, such as `Sonos-38420B60C6CE.local`.
    ///   - port: Its own services' port, which has been 1400 on every speaker seen.
    ///   - timeout: How long to wait for each answer.
    public init(host: String, port: Int = 1400, timeout: TimeInterval = 3) {
        self.host = host
        self.port = port
        self.timeout = timeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        // These answers describe this instant, so one that was cached is worse
        // than no answer at all.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }
}

// MARK: - What it is

public extension SonosClient {
    /// What the speaker says it is.
    ///
    /// One plain request, no SOAP. The description nests the speaker and the
    /// two services it offers, and repeats the same element names inside each,
    /// so what is read is the outermost of them.
    func device() async throws -> SonosDevice {
        let data = try await get(path: "/xml/device_description.xml")
        let values = firstValues(of: ["roomName", "displayName", "modelName",
                                      "modelNumber", "UDN", "url"], in: data)

        guard let identifier = values["UDN"] else {
            throw SonosError.unexpectedAnswer(missing: "UDN")
        }

        // The identifier is published as a URN and named everywhere else
        // without the prefix, which is the form a zone group uses.
        let prefix = "uuid:"
        let bare = identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier

        return SonosDevice(roomName: values["roomName"] ?? "",
                           displayName: values["displayName"] ?? "",
                           modelName: values["modelName"] ?? "",
                           modelNumber: values["modelNumber"] ?? "",
                           identifier: bare,
                           iconPath: values["url"])
    }

    /// Where the speaker serves a picture of itself, or `nil` where it named none.
    ///
    /// The picture is a plain HTTP request to the same host, so it needs nothing
    /// shipped with an application and stays right when a model is replaced.
    func iconURL(for device: SonosDevice) -> URL? {
        guard let path = device.iconPath else { return nil }

        return address(of: path)
    }
}

// MARK: - What it is doing

public extension SonosClient {
    /// What the speaker is doing at this moment.
    ///
    /// Three requests, because the speaker answers them separately: the
    /// transport's state, the volume and the mute. They are made one after
    /// another, so this describes an instant a few milliseconds wide rather
    /// than one exact instant.
    func playback() async throws -> SonosPlayback {
        let transport = try await call(service: .avTransport, action: "GetTransportInfo",
                                       arguments: "<InstanceID>0</InstanceID>")
        let volume = try await call(service: .renderingControl, action: "GetVolume",
                                    arguments: "<InstanceID>0</InstanceID><Channel>Master</Channel>")
        let mute = try await call(service: .renderingControl, action: "GetMute",
                                  arguments: "<InstanceID>0</InstanceID><Channel>Master</Channel>")

        guard let reported = firstValues(of: ["CurrentTransportState"], in: transport)["CurrentTransportState"] else {
            throw SonosError.unexpectedAnswer(missing: "CurrentTransportState")
        }
        guard let level = firstValues(of: ["CurrentVolume"], in: volume)["CurrentVolume"].flatMap(Int.init) else {
            throw SonosError.unexpectedAnswer(missing: "CurrentVolume")
        }
        guard let muted = firstValues(of: ["CurrentMute"], in: mute)["CurrentMute"] else {
            throw SonosError.unexpectedAnswer(missing: "CurrentMute")
        }

        return SonosPlayback(state: SonosTransportState(reported: reported),
                             volume: level,
                             isMuted: muted != "0",
                             followingIdentifier: try await coordinatorBeingFollowed())
    }

    /// Which speaker this one is following, or `nil` when it plays its own audio.
    ///
    /// A speaker in a group reports the coordinator it follows in place of a
    /// track, under an address beginning `x-rincon:`. Everything else about
    /// what is playing then belongs to the coordinator rather than to this one.
    private func coordinatorBeingFollowed() async throws -> String? {
        let position = try await call(service: .avTransport, action: "GetPositionInfo",
                                      arguments: "<InstanceID>0</InstanceID>")

        guard let address = firstValues(of: ["TrackURI"], in: position)["TrackURI"] else { return nil }

        let prefix = "x-rincon:"
        guard address.hasPrefix(prefix) else { return nil }

        return String(address.dropFirst(prefix.count))
    }
}

// MARK: - Which speakers play together

public extension SonosClient {
    /// Every group on the network, as this speaker sees them.
    ///
    /// Any speaker answers for the whole network, so this is asked of whichever
    /// one is to hand rather than of each in turn.
    ///
    /// Every speaker is always in a group, and one playing alone is in a group
    /// of itself, which ``SonosZoneGroup/isAlone`` separates. A bonded set, such
    /// as a soundbar with its surrounds, appears as one group whose members
    /// share a room name.
    func zoneGroups() async throws -> [SonosZoneGroup] {
        let state = try await call(service: .zoneGroupTopology, action: "GetZoneGroupState",
                                   arguments: "<InstanceID>0</InstanceID>")

        return readZoneGroups(in: state)
    }
}

// MARK: - Where a request goes

extension SonosClient {
    /**
     The address of one path on this speaker, or nil where the two do not make
     one.

     Built out of components rather than written into a string, because neither
     half is this package's to trust. The host arrives in a Bonjour record that
     anything on the network can publish, and a path can arrive in the speaker's
     own description, which is a third party's answer. A host carrying a slash or
     an at sign, or a path carrying a scheme, written into a string sends the
     request somewhere other than the speaker, and nothing about the result would
     look wrong.

     `URLComponents` knows the grammar and either escapes what it is given or
     refuses to make a URL at all, so whatever comes back addresses this speaker
     and this port or is nothing.

     - Parameter path: What to ask for, beginning with a slash.
     - Returns: The address, or nil where the host or the path cannot be part of
       one.
     */
    func address(of path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path

        guard let url = components.url else { return nil }

        // Read back rather than trusted. Escaping is only half of the guarantee
        // that matters here, and the half that matters is that the request goes
        // to the speaker that was named. Anything else is refused outright.
        guard url.host == host else { return nil }

        return url
    }
}

// MARK: - Speaking UPnP

private extension SonosClient {
    /// The three services this asks anything of, and where each one listens.
    enum Service {
        case avTransport
        case renderingControl
        case zoneGroupTopology

        /// The path its control endpoint sits at.
        var path: String {
            switch self {
            case .avTransport: return "/MediaRenderer/AVTransport/Control"
            case .renderingControl: return "/MediaRenderer/RenderingControl/Control"
            case .zoneGroupTopology: return "/ZoneGroupTopology/Control"
            }
        }

        /// The service type, which goes in the body and in the action header.
        var urn: String {
            switch self {
            case .avTransport: return "urn:schemas-upnp-org:service:AVTransport:1"
            case .renderingControl: return "urn:schemas-upnp-org:service:RenderingControl:1"
            case .zoneGroupTopology: return "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
            }
        }
    }

    /// Calls one action and hands back the answer as it arrived.
    func call(service: Service, action: String, arguments: String) async throws -> Data {
        guard let url = address(of: service.path) else {
            throw SonosError.unreachable
        }

        let body = """
            <?xml version="1.0"?>\
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
            <s:Body><u:\(action) xmlns:u="\(service.urn)">\(arguments)</u:\(action)></s:Body>\
            </s:Envelope>
            """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        return try await send(request)
    }

    /// Fetches one document, with no SOAP around it.
    func get(path: String) async throws -> Data {
        guard let url = address(of: path) else {
            throw SonosError.unreachable
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        return try await send(request)
    }

    /// Sends a request and hands back its body, or says why it could not.
    ///
    /// Wrapped by hand rather than through the asynchronous method on
    /// `URLSession`, because that one is not offered by every Foundation this
    /// package builds against and a continuation is offered by all of them.
    func send(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if error != nil {
                    continuation.resume(throwing: SonosError.unreachable)
                    return
                }

                if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                    continuation.resume(throwing: SonosError.refused(status: status))
                    return
                }

                guard let data else {
                    continuation.resume(throwing: SonosError.unreachable)
                    return
                }

                continuation.resume(returning: data)
            }

            task.resume()
        }
    }
}
