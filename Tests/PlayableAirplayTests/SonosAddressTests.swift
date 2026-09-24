//
//  SonosAddressTests.swift
//  That a request to a speaker goes to that speaker and nowhere else.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplayUPnP

/**
 Where a request to a Sonos actually goes.

 Both halves of the address come off the network. The host arrives in a Bonjour
 record, which anything on the network can publish, and a path can arrive in the
 speaker's own description, which is a third party's answer. Written into a
 string, either one can carry the request to a different machine, and the result
 looks exactly like an ordinary request.

 So the property here is one sentence: whatever comes back addresses the host
 that was named, or it is nothing.
 */
final class SonosAddressTests: XCTestCase {

    /// Hosts that would leave the speaker if they were written into a string.
    private let hostileHosts = [
        "speaker.local/@evil.example",
        "speaker.local@evil.example",
        "evil.example#speaker.local",
        "speaker.local:80@evil.example",
        "speaker.local/../../evil.example",
        "speaker.local?x=@evil.example",
        "",
        "speaker.local ",
        "speaker\u{0000}.local",
    ]

    /// Paths a speaker could put in its own description.
    private let hostilePaths = [
        "//evil.example/picture.png",
        "http://evil.example/picture.png",
        "/../../../etc/passwd",
        "/picture.png?x=1",
        "/picture.png#fragment",
        "picture.png",
        "",
    ]

    // MARK: - The ordinary case

    func testAnOrdinaryPathOnAnOrdinarySpeaker() throws {
        let speaker = SonosClient(host: "Sonos-38420B60C6CE.local")
        let url = try XCTUnwrap(speaker.address(of: "/xml/device_description.xml"))

        XCTAssertEqual(url.absoluteString,
                       "http://Sonos-38420B60C6CE.local:1400/xml/device_description.xml")
    }

    func testThePortIsTheOneTheSpeakerWasGiven() throws {
        let speaker = SonosClient(host: "speaker.local", port: 1401)
        let url = try XCTUnwrap(speaker.address(of: "/ZoneGroupTopology/Control"))

        XCTAssertEqual(url.port, 1401)
        XCTAssertEqual(url.host, "speaker.local")
    }

    // MARK: - A host that tries to leave

    func testNoHostSendsTheRequestSomewhereElse() {
        for host in hostileHosts {
            let speaker = SonosClient(host: host)

            guard let url = speaker.address(of: "/xml/device_description.xml") else { continue }

            XCTAssertEqual(url.host, host, "\(host) addressed something else")
        }
    }

    func testTheThreeHostsThatUsedToLeadSomewhereElseAreRefused() {
        // Not hypothetical. Written into a string, each of these three produced
        // a URL whose host was evil.example, and the first two put the
        // speaker's name in front of the at sign where it reads as the
        // destination whilst being the username:
        //
        //   speaker.local@evil.example    -> host=evil.example user=speaker.local
        //   speaker.local:80@evil.example -> host=evil.example user=speaker.local
        //   evil.example#speaker.local    -> host=evil.example
        //
        // Nil rather than corrected, because a host that is not a host is not
        // something to guess the intent of.
        for host in ["speaker.local@evil.example",
                     "speaker.local:80@evil.example",
                     "evil.example#speaker.local"] {
            XCTAssertNil(SonosClient(host: host).address(of: "/xml/device_description.xml"), host)
        }
    }

    func testNoHostIsGivenAUserOrAPassword() {
        // Everything before an at sign in an authority is credentials, and a
        // request that carries them is a request to somewhere else.
        for host in hostileHosts {
            guard let url = SonosClient(host: host).address(of: "/x") else { continue }

            XCTAssertNil(url.user, host)
            XCTAssertNil(url.password, host)
        }
    }

    // MARK: - A path that tries to leave

    func testNoPathFromTheSpeakerSendsTheRequestSomewhereElse() {
        let speaker = SonosClient(host: "speaker.local")

        for path in hostilePaths {
            guard let url = speaker.address(of: path) else { continue }

            XCTAssertEqual(url.host, "speaker.local", "\(path) addressed something else")
        }
    }

    func testAPathThatLooksLikeAnAuthorityStaysAPath() {
        // `//evil.example/x` written after a host in a string is still a path,
        // but one built from it by hand is a different authority. This is the
        // shape that catches people out, so it is pinned rather than reasoned
        // about.
        let speaker = SonosClient(host: "speaker.local")

        guard let url = speaker.address(of: "//evil.example/picture.png") else { return }

        XCTAssertEqual(url.host, "speaker.local")
    }

    // MARK: - The picture the speaker names

    func testTheIconAddressIsOnTheSpeakerThatNamedIt() throws {
        let speaker = SonosClient(host: "speaker.local")
        let device = SonosDevice(roomName: "Wohnzimmer",
                                 displayName: "Sonos One",
                                 modelName: "One",
                                 modelNumber: "S13",
                                 identifier: "RINCON_1",
                                 iconPath: "/img/icon-S13.png")

        let url = try XCTUnwrap(speaker.iconURL(for: device))

        XCTAssertEqual(url.absoluteString, "http://speaker.local:1400/img/icon-S13.png")
    }

    func testASpeakerThatNamesNoPictureHasNoAddressForOne() {
        let speaker = SonosClient(host: "speaker.local")
        let device = SonosDevice(roomName: "Wohnzimmer",
                                 displayName: "Sonos One",
                                 modelName: "One",
                                 modelNumber: "S13",
                                 identifier: "RINCON_1",
                                 iconPath: nil)

        XCTAssertNil(speaker.iconURL(for: device))
    }

    func testAPictureNamedOnAnotherMachineIsNotFetched() {
        let speaker = SonosClient(host: "speaker.local")
        let device = SonosDevice(roomName: "Wohnzimmer",
                                 displayName: "Sonos One",
                                 modelName: "One",
                                 modelNumber: "S13",
                                 identifier: "RINCON_1",
                                 iconPath: "//evil.example/picture.png")

        guard let url = speaker.iconURL(for: device) else { return }

        XCTAssertEqual(url.host, "speaker.local")
    }
}
