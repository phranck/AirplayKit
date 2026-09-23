//
//  SonosReadingTests.swift
//  Reading the documents a speaker answers with, without a speaker.
//
//  Every document below was captured from a Sonos One on 2026-09-22 and
//  trimmed to the elements that are read. Addresses and identifiers are
//  replaced; the structure is exactly as it arrived, because the structure is
//  what is being checked.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest

@testable import PlayableAirplayUPnP

final class SonosReadingTests: XCTestCase {
    // MARK: - What a speaker says it is

    /// A device description nests three devices and repeats the same element
    /// names inside each, which is the trap this document exists to hold.
    private let deviceDescription = """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>192.0.2.30 - Sonos One - RINCON_AAAABBBBCCCC01400</friendlyName>
            <modelNumber>S18</modelNumber>
            <modelName>Sonos One</modelName>
            <UDN>uuid:RINCON_AAAABBBBCCCC01400</UDN>
            <iconList><icon><url>/img/icon-S18.png</url></icon></iconList>
            <roomName>Kitchen</roomName>
            <displayName>One</displayName>
            <deviceList>
              <device>
                <modelNumber>S18</modelNumber>
                <modelName>Sonos One Media Server</modelName>
                <UDN>uuid:RINCON_AAAABBBBCCCC01400_MS</UDN>
              </device>
            </deviceList>
          </device>
        </root>
        """

    func testTheOutermostDeviceIsTheSpeakerAndNotOneOfItsServices() {
        let values = firstValues(of: ["roomName", "displayName", "modelName", "modelNumber", "UDN", "url"],
                                 in: Data(deviceDescription.utf8))

        XCTAssertEqual(values["roomName"], "Kitchen")
        XCTAssertEqual(values["displayName"], "One")
        XCTAssertEqual(values["modelName"], "Sonos One")
        XCTAssertEqual(values["modelNumber"], "S18")
        XCTAssertEqual(values["UDN"], "uuid:RINCON_AAAABBBBCCCC01400")
        XCTAssertEqual(values["url"], "/img/icon-S18.png")
    }

    func testAnElementThatIsNotThereIsAbsentRatherThanEmpty() {
        let values = firstValues(of: ["roomName", "nothingLikeThis"], in: Data(deviceDescription.utf8))

        XCTAssertEqual(values["roomName"], "Kitchen")
        XCTAssertNil(values["nothingLikeThis"])
    }

    /// A room name is typed by a person, so it arrives escaped and has to come
    /// back as what they typed.
    func testAnEscapedRoomNameComesBackAsItWasTyped() {
        let document = "<root><roomName>Bob &amp; Jane&apos;s Room</roomName></root>"
        let values = firstValues(of: ["roomName"], in: Data(document.utf8))

        XCTAssertEqual(values["roomName"], "Bob & Jane's Room")
    }

    // MARK: - What a speaker is doing

    func testTheTransportStateIsReadOutOfItsEnvelope() {
        let answer = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">\
            <s:Body><u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">\
            <CurrentTransportState>PLAYING</CurrentTransportState>\
            <CurrentTransportStatus>OK</CurrentTransportStatus>\
            <CurrentSpeed>1</CurrentSpeed>\
            </u:GetTransportInfoResponse></s:Body></s:Envelope>
            """

        let state = firstValues(of: ["CurrentTransportState"], in: Data(answer.utf8))["CurrentTransportState"]

        XCTAssertEqual(state, "PLAYING")
        XCTAssertEqual(SonosTransportState(reported: state ?? ""), .playing)
    }

    func testAStateNobodyPlannedForIsKeptRatherThanRefused() {
        XCTAssertEqual(SonosTransportState(reported: "PAUSED_PLAYBACK"), .pausedPlayback)
        XCTAssertEqual(SonosTransportState(reported: "SOMETHING_NEW"), .other)
    }

    // MARK: - Which speakers play together

    /// Two groups as they were measured. The first is a soundbar with two
    /// surrounds bonded into it, which is one member and not three. The second
    /// is three rooms somebody put together, which is three members.
    private let topology = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">\
        <s:Body><u:GetZoneGroupStateResponse xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1">\
        <ZoneGroupState>&lt;ZoneGroupState&gt;&lt;ZoneGroups&gt;\
        &lt;ZoneGroup Coordinator="RINCON_BAR01400" ID="RINCON_BAR01400:1"&gt;\
        &lt;ZoneGroupMember UUID="RINCON_BAR01400" ZoneName="Living Room"&gt;\
        &lt;Satellite UUID="RINCON_LEFT01400" ZoneName="Living Room" Invisible="1"/&gt;\
        &lt;Satellite UUID="RINCON_RIGHT01400" ZoneName="Living Room" Invisible="1"/&gt;\
        &lt;/ZoneGroupMember&gt;&lt;/ZoneGroup&gt;\
        &lt;ZoneGroup Coordinator="RINCON_ONE01400" ID="RINCON_ONE01400:2"&gt;\
        &lt;ZoneGroupMember UUID="RINCON_ONE01400" ZoneName="Kitchen"/&gt;\
        &lt;ZoneGroupMember UUID="RINCON_TWO01400" ZoneName="Bathroom"/&gt;\
        &lt;ZoneGroupMember UUID="RINCON_THREE01400" ZoneName="Balcony"/&gt;\
        &lt;/ZoneGroup&gt;&lt;/ZoneGroups&gt;&lt;/ZoneGroupState&gt;</ZoneGroupState>\
        </u:GetZoneGroupStateResponse></s:Body></s:Envelope>
        """

    func testTheTopologyIsReadOutOfTheDocumentInsideTheDocument() {
        let groups = readZoneGroups(in: Data(topology.utf8))

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.coordinatorIdentifier, "RINCON_BAR01400")
    }

    func testABondedSetIsOneMemberWithSatellitesRatherThanThreeMembers() {
        guard let bonded = readZoneGroups(in: Data(topology.utf8)).first else {
            return XCTFail("the first group is missing")
        }

        XCTAssertEqual(bonded.members.count, 1)
        XCTAssertEqual(bonded.members.first?.satellites.count, 2)
        XCTAssertEqual(bonded.members.first?.isBonded, true)

        // Three speakers in one room, playing by themselves. Saying that this
        // group joins several members would read as somebody having grouped it.
        XCTAssertFalse(bonded.joinsSeveralMembers)
    }

    func testRoomsSomebodyPutTogetherAreSeveralMembers() {
        guard let joined = readZoneGroups(in: Data(topology.utf8)).last else {
            return XCTFail("the second group is missing")
        }

        XCTAssertEqual(joined.members.map(\.roomName), ["Kitchen", "Bathroom", "Balcony"])
        XCTAssertTrue(joined.joinsSeveralMembers)
        XCTAssertEqual(joined.members.first?.satellites, [])
    }

    func testAnAnswerCarryingNoTopologyIsNoGroupsRatherThanAFailure() {
        let empty = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body/></s:Envelope>"

        XCTAssertEqual(readZoneGroups(in: Data(empty.utf8)), [])
    }

    // MARK: - The two volume scales

    func testTheTwoVolumeScalesMeetAtTheEndsAndInTheMiddle() {
        XCTAssertEqual(SonosVolume.fromFraction(0), 0)
        XCTAssertEqual(SonosVolume.fromFraction(0.5), 50)
        XCTAssertEqual(SonosVolume.fromFraction(1), 100)

        XCTAssertEqual(SonosVolume.fraction(from: 0), 0)
        XCTAssertEqual(SonosVolume.fraction(from: 50), 0.5)
        XCTAssertEqual(SonosVolume.fraction(from: 100), 1)
    }

    /// A caller handing over something outside the scale gets the nearest end of
    /// it rather than a speaker asked for a volume it has no setting for.
    func testAValueOutsideEitherScaleIsBroughtBackIntoIt() {
        XCTAssertEqual(SonosVolume.fromFraction(-1), 0)
        XCTAssertEqual(SonosVolume.fromFraction(4), 100)

        XCTAssertEqual(SonosVolume.fraction(from: -10), 0)
        XCTAssertEqual(SonosVolume.fraction(from: 400), 1)
    }
}
