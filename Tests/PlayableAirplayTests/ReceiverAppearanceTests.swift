//
//  ReceiverAppearanceTests.swift
//  What a receiver is called and what it is drawn as.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplay

/**
 Naming and drawing a receiver from what it publishes.

 Every value below was read off a real network on 2026-09-24 rather than made
 up, because the whole point of this is that the two cases are told apart by a
 field being absent, and a made-up record would not have that shape.
 */
final class ReceiverAppearanceTests: XCTestCase {

    private func receiver(model: String, manufacturer: String = "") -> AirPlayReceiver {
        AirPlayReceiver(id: "test",
                        name: "Room",
                        host: "test.local.",
                        port: 7000,
                        model: model,
                        manufacturer: manufacturer,
                        groupID: "",
                        supportsAirPlay2: true,
                        hasSender: false,
                        isPlaying: false)
    }

    // MARK: - Telling the two cases apart

    func testAReceiverThatPublishesAManufacturerIsSomebodyElsesSpeaker() {
        XCTAssertEqual(receiver(model: "One", manufacturer: "Sonos").kind, .speaker)
        XCTAssertEqual(receiver(model: "Bookshelf", manufacturer: "Sonos").kind, .speaker)
        XCTAssertEqual(receiver(model: "Arc", manufacturer: "Sonos").kind, .speaker)
    }

    func testApplesReceiversPublishNoManufacturerAndAreKnownByTheirIdentifier() {
        XCTAssertEqual(receiver(model: "AudioAccessory5,1").kind, .homePodMini)
        XCTAssertEqual(receiver(model: "AudioAccessory1,1").kind, .homePod)
        XCTAssertEqual(receiver(model: "AudioAccessory6,1").kind, .homePod)
        XCTAssertEqual(receiver(model: "AppleTV11,1").kind, .appleTV)
        XCTAssertEqual(receiver(model: "Macmini9,1").kind, .mac)
        XCTAssertEqual(receiver(model: "Mac16,12").kind, .mac)
    }

    func testAReceiverThatSaidNothingIsNothing() {
        XCTAssertEqual(receiver(model: "").kind, .unknown)
        XCTAssertEqual(receiver(model: "Something").kind, .unknown)
    }

    func testAManufacturerWithoutAModelIsStillASpeaker() {
        // Nothing says both fields arrive, and a speaker with only one of them
        // is still a speaker rather than an unknown.
        XCTAssertEqual(receiver(model: "", manufacturer: "Sonos").kind, .speaker)
    }

    // MARK: - What it is called

    func testSomebodyElsesSpeakerIsNamedByJoiningTheTwoFields() {
        XCTAssertEqual(receiver(model: "One", manufacturer: "Sonos").productName, "Sonos One")
        XCTAssertEqual(receiver(model: "Arc", manufacturer: "Sonos").productName, "Sonos Arc")
    }

    func testAMissingHalfDoesNotLeaveAStraySpace() {
        XCTAssertEqual(receiver(model: "", manufacturer: "Sonos").productName, "Sonos")
    }

    func testAReceiverThatSaidNothingIsCalledNothing() {
        // Shown as nothing rather than as the word "unknown", which is a caller's
        // decision and is easier to make from an empty string.
        XCTAssertEqual(receiver(model: "").productName, "")
    }

    func testTheFamilyIsAsFarAsAnIdentifierGoesOnItsOwn() {
        // The fallback for a model newer than the table. Exact for the families
        // that carry their name, and no further for a Mac, because a Mac16,12
        // is a MacBook Air and a Mac16,11 is a Mac mini and nothing in the
        // identifier says which.
        XCTAssertEqual(AirPlayReceiver.familyName(for: "AudioAccessory5,1"), "HomePod mini")
        XCTAssertEqual(AirPlayReceiver.familyName(for: "AudioAccessory1,2"), "HomePod")
        XCTAssertEqual(AirPlayReceiver.familyName(for: "AppleTV11,1"), "Apple TV")
        XCTAssertEqual(AirPlayReceiver.familyName(for: "Mac16,12"), "Mac")
        XCTAssertEqual(AirPlayReceiver.familyName(for: "Macmini9,1"), "Mac")
    }

    func testTheTableGivesTheExactProduct() {
        // The reason for carrying the table at all: it separates two machines
        // that the identifier alone does not.
        XCTAssertEqual(receiver(model: "AudioAccessory5,1").productName, "HomePod mini")
        XCTAssertEqual(receiver(model: "Mac16,12").productName, "MacBook Air")
        XCTAssertEqual(receiver(model: "Macmini9,1").productName, "Mac mini")
    }

    func testAnIdentifierTheTableDoesNotCarryFallsBackToTheFamily() {
        // A model released after the table was taken. The family is still in
        // the identifier, so it is named rather than left blank.
        XCTAssertEqual(receiver(model: "AppleTV99,9").productName, "Apple TV")
    }

    // MARK: - What it is drawn as

    func testApplesHardwareIsDrawnAsItself() {
        XCTAssertEqual(receiver(model: "AudioAccessory5,1").symbolName, "homepod.mini")
        XCTAssertEqual(receiver(model: "AudioAccessory1,1").symbolName, "homepod")
        XCTAssertEqual(receiver(model: "AppleTV11,1").symbolName, "appletv")
    }

    func testEverybodyElseIsDrawnAsASpeaker() {
        // The catalogue has nothing shaped like a Sonos, and no soundbar at all,
        // so an Arc and a One are the same picture. At the size a list uses they
        // would be anyway.
        XCTAssertEqual(receiver(model: "One", manufacturer: "Sonos").symbolName, "hifispeaker")
        XCTAssertEqual(receiver(model: "Arc", manufacturer: "Sonos").symbolName, "hifispeaker")
        XCTAssertEqual(receiver(model: "").symbolName, "hifispeaker")
    }

    func testAPairIsDrawnAsAPair() {
        XCTAssertEqual(receiver(model: "One", manufacturer: "Sonos").pairSymbolName, "hifispeaker.2")
        XCTAssertEqual(receiver(model: "AudioAccessory5,1").pairSymbolName, "homepod.mini.2")
        XCTAssertEqual(receiver(model: "AudioAccessory1,1").pairSymbolName, "homepod.2")
    }

    func testAThingThatDoesNotPairIsDrawnAsItself() {
        // Two Apple TVs are not a stereo set, so there is no pair symbol for
        // them and the single one stands.
        let appleTV = receiver(model: "AppleTV11,1")

        XCTAssertEqual(appleTV.pairSymbolName, appleTV.symbolName)
    }

    func testAMacIsDrawnByWhatItIsCalledRatherThanByItsIdentifier() {
        // The identifier stopped saying what the machine is when it became
        // Mac16,x. The name still says it.
        XCTAssertEqual(AirPlayReceiver.macSymbolName(for: "MacBook Air"), "laptopcomputer")
        XCTAssertEqual(AirPlayReceiver.macSymbolName(for: "Mac mini"), "macmini.gen3")
        XCTAssertEqual(AirPlayReceiver.macSymbolName(for: "Mac Studio"), "macstudio")
        XCTAssertEqual(AirPlayReceiver.macSymbolName(for: "Mac Pro"), "macpro.gen3")
        XCTAssertEqual(AirPlayReceiver.macSymbolName(for: "iMac"), "desktopcomputer")
    }
}
