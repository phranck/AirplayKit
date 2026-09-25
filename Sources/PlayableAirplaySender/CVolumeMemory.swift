//
//  CVolumeMemory.swift
//  Opaque C lifetime for the shared receiver volume store.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

package func heldVolumeMemory(_ pointer: UnsafeMutableRawPointer?) -> ReceiverVolumeMemory? {
    guard let pointer else { return nil }
    return Unmanaged<ReceiverVolumeMemory>.fromOpaque(pointer).takeUnretainedValue()
}

@_cdecl("pa_volume_memory_open")
package func pa_volume_memory_open(_ path: UnsafePointer<CChar>?,
                                   _ enabled: Bool,
                                   _ result: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    guard let path, !String(cString: path).isEmpty else {
        result?.pointee = CResult.invalidArgument.rawValue
        return nil
    }
    do {
        let memory = try ReceiverVolumeMemory(fileURL: URL(fileURLWithPath: String(cString: path)),
                                              enabled: enabled)
        result?.pointee = CResult.ok.rawValue
        return Unmanaged.passRetained(memory).toOpaque()
    } catch {
        result?.pointee = CResult.internalFailure.rawValue
        return nil
    }
}

@_cdecl("pa_volume_memory_set_enabled")
package func pa_volume_memory_set_enabled(_ pointer: UnsafeMutableRawPointer?, _ enabled: Bool) {
    heldVolumeMemory(pointer)?.isEnabled = enabled
}

@_cdecl("pa_volume_memory_is_enabled")
package func pa_volume_memory_is_enabled(_ pointer: UnsafeMutableRawPointer?) -> Bool {
    heldVolumeMemory(pointer)?.isEnabled ?? false
}

@_cdecl("pa_volume_memory_last_error")
package func pa_volume_memory_last_error(_ pointer: UnsafeMutableRawPointer?,
                                         _ out: UnsafeMutablePointer<CChar>?,
                                         _ capacity: Int) -> Int {
    let bytes = Array((heldVolumeMemory(pointer)?.lastErrorDescription ?? "").utf8)
    if let out, capacity > 0 {
        let copied = min(bytes.count, capacity - 1)
        for index in 0..<copied { out[index] = CChar(bitPattern: bytes[index]) }
        out[copied] = 0
    }
    return bytes.count
}

@_cdecl("pa_volume_memory_close")
package func pa_volume_memory_close(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer else { return }
    Unmanaged<ReceiverVolumeMemory>.fromOpaque(pointer).release()
}
