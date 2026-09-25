//
//  ReceiverVolumeMemoryTests.swift
//  Persistence stays inside uniquely owned temporary directories.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import XCTest

@testable import PlayableAirplaySender

final class ReceiverVolumeMemoryTests: XCTestCase {
    func testConfirmedLevelsSurviveASecondInstanceAndStaySeparateByReceiver() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayableAirplay-volume-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("volumes.json")

        let first = try ReceiverVolumeMemory(fileURL: file, enabled: true)
        XCTAssertTrue(first.remember(0.3, for: "office"))
        XCTAssertTrue(first.remember(0.7, for: "dining"))

        let second = try ReceiverVolumeMemory(fileURL: file, enabled: true)
        XCTAssertEqual(second.storedVolume(for: "office"), 0.3)
        XCTAssertEqual(second.storedVolume(for: "dining"), 0.7)
        XCTAssertNil(second.storedVolume(for: "unknown"))
    }

    func testDisabledModeNeitherRecordsNorRestoresAndKeepsTheExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayableAirplay-volume-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("volumes.json")

        let memory = try ReceiverVolumeMemory(fileURL: file, enabled: true)
        XCTAssertTrue(memory.remember(0.4, for: "office"))
        memory.isEnabled = false
        XCTAssertNil(memory.storedVolume(for: "office"))
        XCTAssertTrue(memory.remember(0.8, for: "office"))
        memory.isEnabled = true
        XCTAssertEqual(memory.storedVolume(for: "office"), 0.4)
    }

    func testRestorationAppliesOnlySavedVolumeWhenEnabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayableAirplay-volume-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = try ReceiverVolumeMemory(fileURL: directory.appendingPathComponent("volumes.json"), enabled: true)
        XCTAssertTrue(memory.remember(0.25, for: "office"))

        var applied: [Float] = []
        try memory.restoreVolume(for: "office") { applied.append($0) }
        try memory.restoreVolume(for: "unknown") { applied.append($0) }
        memory.isEnabled = false
        try memory.restoreVolume(for: "office") { applied.append($0) }
        XCTAssertEqual(applied, [0.25])
    }

    func testCorruptFileIsRejectedWithoutReplacingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayableAirplay-volume-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("volumes.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: file)

        XCTAssertThrowsError(try ReceiverVolumeMemory(fileURL: file, enabled: true))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testWriteFailureIsVisibleAndDoesNotClaimToHaveSavedTheLevel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayableAirplay-volume-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("blocked")
        try Data("occupied".utf8).write(to: blocked)
        let memory = try ReceiverVolumeMemory(fileURL: blocked.appendingPathComponent("volumes.json"), enabled: true)

        XCTAssertFalse(memory.remember(0.5, for: "office"))
        XCTAssertNil(memory.storedVolume(for: "office"))
        XCTAssertNotNil(memory.lastErrorDescription)
    }
}
