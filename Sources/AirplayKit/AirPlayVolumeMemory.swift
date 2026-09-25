//
//  AirPlayVolumeMemory.swift
//  Optional, application-owned persistence for receiver volume.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import AirplayKitSender

/// Remembers the last confirmed volume for each stable receiver ID.
///
/// The caller chooses the storage URL and owns this object. The feature starts
/// disabled unless explicitly enabled. Disabling retains the file but stops
/// restoration and writes. A receiver changed while disconnected will receive
/// the saved level when it next joins a session.
public final class AirPlayVolumeMemory {
    package let storage: ReceiverVolumeMemory

    /// Reads an existing volume file or prepares an empty in-memory store.
    /// Invalid or unreadable files throw without replacing their contents.
    public init(fileURL: URL, enabled: Bool = false) throws {
        storage = try ReceiverVolumeMemory(fileURL: fileURL, enabled: enabled)
    }

    /// Whether sessions using this object restore and record receiver volumes.
    public var isEnabled: Bool {
        get { storage.isEnabled }
        set { storage.isEnabled = newValue }
    }

    /// The most recent write error, if persistence failed after initialization.
    public var lastStorageError: String? { storage.lastErrorDescription }
}
