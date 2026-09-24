//
//  DeviceClassificationTests.swift
//  That naming a device and drawing it never disagree about what it is.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplayDevices

/**
 One classification, read two ways.

 Naming and drawing used to work the family out separately from the same three
 prefix tests, so a device could be called "Mac" and drawn as somebody else's
 speaker. Nothing reported that, because each half was right about itself.

 What follows walks every identifier the package carries a name for and asks the
 two questions about each of them. The property is one-directional and is
 exactly the failure: where the library names something as Apple's hardware, it
 must not then draw it as a stranger's speaker.
 */
final class DeviceClassificationTests: XCTestCase {

    /// What the library draws anything it does not recognise as.
    private let strangersSpeaker = "hifispeaker.fill"

    /**
     The family a name belongs to, or nil where the name says nothing.

     Worked out from the name rather than from the identifier on purpose,
     because the identifier is what the library classifies by and a test that
     read it too would agree with the library by construction.
     */
    private func familyInName(_ name: String) -> String? {
        if name.hasPrefix("HomePod") { return "HomePod" }
        if name.hasPrefix("Apple TV") && !name.contains("Remote") { return "Apple TV" }
        if name.hasPrefix("Mac") || name.hasPrefix("iMac") { return "Mac" }

        return nil
    }

    func testNothingNamedAsApplesHardwareIsDrawnAsAStrangersSpeaker() {
        var disagreed: [String] = []

        for (identifier, _) in DeviceModelNames.all {
            let name = DeviceAppearance.productName(manufacturer: "", model: identifier)
            guard let family = familyInName(name) else { continue }

            let symbol = DeviceAppearance.symbolName(manufacturer: "", model: identifier)
            guard symbol == strangersSpeaker else { continue }

            disagreed.append("\(identifier) is named \(name), a \(family), and drawn as \(symbol)")
        }

        XCTAssertEqual(disagreed.sorted(), [], "naming and drawing disagree")
    }

    func testAHomePodIsNeverDrawnAsAnAppleTVOrTheOtherWayRound() {
        // The families the catalogue has a symbol of its own for. Getting one of
        // these wrong draws the right kind of device as the wrong product, which
        // is more misleading than drawing it as a generic speaker.
        let expected = ["HomePod": ["homepod.fill", "homepod.mini.fill"],
                        "Apple TV": ["appletv.fill"]]
        var wrong: [String] = []

        for (identifier, _) in DeviceModelNames.all {
            let name = DeviceAppearance.productName(manufacturer: "", model: identifier)
            guard let family = familyInName(name), let allowed = expected[family] else { continue }

            let symbol = DeviceAppearance.symbolName(manufacturer: "", model: identifier)
            guard !allowed.contains(symbol) else { continue }

            wrong.append("\(identifier) is named \(name) and drawn as \(symbol)")
        }

        XCTAssertEqual(wrong.sorted(), [], "a family is drawn as something else")
    }

    func testEveryMacInTheTableIsDrawnAsTheMacItIsNamed() {
        // The same defect one layer down: the name says which Mac and the
        // symbol says a different one. The names overlap, so this is about the
        // order the tests are made in.
        let expected = ["MacBook Pro": "laptopcomputer",
                        "MacBook Air": "laptopcomputer",
                        "MacBook Neo": "laptopcomputer",
                        "iMac": "desktopcomputer",
                        "iMac G5": "desktopcomputer",
                        "iMac Pro": "desktopcomputer",
                        "Mac mini": "macmini.gen3.fill",
                        "Mac Mini": "macmini.gen3.fill",
                        "Mac Studio": "macstudio.fill",
                        "Mac Pro": "macpro.gen3.fill",
                        "Mac": "desktopcomputer"]

        for (name, symbol) in expected {
            XCTAssertEqual(DeviceAppearance.macSymbolName(for: name), symbol, "\(name)")
        }
    }

    func testAnIdentifierThatDoesNotSayItIsAMacIsStillAMacWhereItsNameSaysSo() {
        // The identifier that found this. Its name is "Mac" and the identifier
        // begins with neither "Mac" nor "iMac", so classifying by the
        // identifier called it nothing and drew it as a stranger's speaker.
        XCTAssertEqual(DeviceModelNames.name(for: "ADP3,2"), "Mac")
        XCTAssertEqual(DeviceAppearance.kind(manufacturer: "", model: "ADP3,2"), .mac)

        XCTAssertEqual(DeviceModelNames.name(for: "PowerMac6,1"), "iMac")
        XCTAssertEqual(DeviceAppearance.kind(manufacturer: "", model: "PowerMac6,1"), .mac)
    }

    func testANameThatSaysNothingAboutTheFamilyLeavesItUnknown() {
        // `ADP2,1` is the 2005 developer transition machine and the table calls
        // it "Tower". Nothing in either the name or the identifier says which
        // family that is, so it stays unknown rather than being guessed at, and
        // unknown is drawn as a speaker exactly as anything else unrecognised
        // is. The point of this is that the library never invents a family it
        // was not told.
        XCTAssertEqual(DeviceModelNames.name(for: "ADP2,1"), "Tower")
        XCTAssertEqual(DeviceAppearance.kind(manufacturer: "", model: "ADP2,1"), .unknown)
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "ADP2,1"), "Tower")
    }

    func testARemoteIsNotTheAppleTVItWorks() {
        // The only two names in the table beginning with "Apple TV" that are
        // not one, so the family cannot be taken from that prefix alone.
        for remote in ["ATVRemote1,1", "ATVRemote1,2"] {
            XCTAssertEqual(DeviceAppearance.kind(manufacturer: "", model: remote), .unknown, remote)
        }
    }

    func testEveryKindStillAnswersTheSameNameAndSymbolItAlwaysDid() {
        // The classification moved, so the answers that were right before it
        // have to be right after it.
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "AudioAccessory5,1"),
                       "HomePod mini")
        XCTAssertEqual(DeviceAppearance.symbolName(manufacturer: "", model: "AudioAccessory5,1"),
                       "homepod.mini.fill")

        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "AppleTV11,1"),
                       "Apple TV 4K (2nd generation)")
        XCTAssertEqual(DeviceAppearance.symbolName(manufacturer: "", model: "AppleTV11,1"),
                       "appletv.fill")

        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "Sonos"), "Sonos")
        XCTAssertEqual(DeviceAppearance.symbolName(manufacturer: "Sonos", model: "One"),
                       "hifispeaker.fill")
    }

    func testAFamilyTheTableDoesNotCarryStillFallsBackToItsFamilyName() {
        // An identifier newer than the table, which is the case familyName
        // exists for and the one the switch over kind must keep answering.
        XCTAssertNil(DeviceModelNames.name(for: "AudioAccessory99,1"))
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "AudioAccessory99,1"),
                       "HomePod")
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "AppleTV99,1"),
                       "Apple TV")
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "Mac99,1"), "Mac")
    }

    func testSomethingThatIsNotApplesAtAllIsStillItsOwnIdentifier() {
        XCTAssertEqual(DeviceAppearance.productName(manufacturer: "", model: "Nothing1,1"),
                       "Nothing1,1")
        XCTAssertEqual(DeviceAppearance.symbolName(manufacturer: "", model: "Nothing1,1"),
                       "hifispeaker.fill")
    }
}
