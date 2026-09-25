//
//  ReceiverVolumeMemory.swift
//  Application-owned, optional volume memory shared by Swift and C callers.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

package enum ReceiverVolumeMemoryError: Error {
    case invalidContents
}

package final class ReceiverVolumeMemory {
    private let fileURL: URL
    private let lock = NSLock()
    private var levels: [String: Float]
    private var enabled: Bool
    private var storageError: String?

    package init(fileURL: URL, enabled: Bool) throws {
        self.fileURL = fileURL
        self.enabled = enabled
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let decoded = try JSONDecoder().decode([String: Float].self, from: Data(contentsOf: fileURL))
            guard decoded.allSatisfy({ !$0.key.isEmpty && $0.value.isFinite && (0...1).contains($0.value) }) else {
                throw ReceiverVolumeMemoryError.invalidContents
            }
            levels = decoded
        } else {
            levels = [:]
        }
    }

    package var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            lock.unlock()
        }
    }

    package var lastErrorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return storageError
    }

    package func storedVolume(for receiverID: String) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return enabled ? levels[receiverID] : nil
    }

    @discardableResult
    package func remember(_ level: Float, for receiverID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return true }
        guard !receiverID.isEmpty, level.isFinite, (0...1).contains(level) else {
            storageError = "invalid receiver ID or volume"
            return false
        }
        guard levels[receiverID] != level else { return true }

        var updated = levels
        updated[receiverID] = level
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            levels = updated
            storageError = nil
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

    package func restoreVolume(for receiverID: String,
                               using apply: (Float) throws -> Void) throws {
        if let level = storedVolume(for: receiverID) { try apply(level) }
    }
}
