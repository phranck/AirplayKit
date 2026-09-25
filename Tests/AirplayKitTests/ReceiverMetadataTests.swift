//
//  ReceiverMetadataTests.swift
//  Device names learned from standard network descriptions.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest
@testable import AirplayKitDevices

final class ReceiverMetadataTests: XCTestCase {
    func testSSDPUsesTheLocationFromTheRespondingReceiver() {
        let response = Data("""
        HTTP/1.1 200 OK\r
        ST: upnp:rootdevice\r
        LOCATION: http://10.0.0.125:1400/xml/device_description.xml\r
        USN: uuid:example::upnp:rootdevice\r
        \r
        """.utf8)

        XCTAssertEqual(ReceiverMetadata.location(in: response, from: "10.0.0.125")?.absoluteString,
                       "http://10.0.0.125:1400/xml/device_description.xml")
        XCTAssertNil(ReceiverMetadata.location(in: response, from: "10.0.0.126"),
                     "a description on a different host must not be attributed to this receiver")
    }

    func testUPnPRootDeviceModelWinsOverNestedServiceModels() {
        let description = Data("""
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <modelName>SYMFONISK Bookshelf</modelName>
            <deviceList><device><modelName>Media Renderer</modelName></device></deviceList>
          </device>
        </root>
        """.utf8)

        XCTAssertEqual(ReceiverMetadata.modelName(in: description), "SYMFONISK Bookshelf")
    }

    func testUPnPDescriptionWorksForAnotherManufacturerWithoutAModelTable() {
        let description = Data("""
        <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
          <manufacturer>Example Audio</manufacturer>
          <modelName>Studio Speaker 4</modelName>
        </device></root>
        """.utf8)

        XCTAssertEqual(ReceiverMetadata.modelName(in: description), "Studio Speaker 4")
    }

    func testAirPlayInfoCanCompleteAnIncompleteBonjourRecord() throws {
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "manufacturer": "Sonos", "model": "One"
        ], format: .binary, options: 0)

        XCTAssertEqual(ReceiverMetadata.airPlayName(in: info, manufacturer: "", model: "One"),
                       "Sonos One")
    }

    func testStandardDescriptionTakesPrecedenceOverAirPlayShortName() throws {
        let description = Data("<root><device><modelName>SYMFONISK Bookshelf</modelName></device></root>".utf8)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "manufacturer": "Sonos", "model": "Bookshelf"
        ], format: .binary, options: 0)

        XCTAssertEqual(ReceiverMetadata.preferredName(upnp: description, airPlayInfo: info,
                                                       manufacturer: "", model: "Bookshelf"),
                       "SYMFONISK Bookshelf")
    }

    func testPublishedModelRemainsVisibleWhenNoOtherDescriptionIsAvailable() {
        XCTAssertEqual(ReceiverMetadata.preferredName(upnp: nil, airPlayInfo: nil,
                                                       manufacturer: "", model: "One"), "One")
    }
}
