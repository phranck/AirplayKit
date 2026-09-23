//
//  CAppearance.swift
//  Naming and drawing a device, seen from C.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// Copies a Swift string into a C buffer, leaving it empty rather than overrunning.
///
/// - Parameters:
///   - text: What to write.
///   - out: Where to write it.
///   - capacity: How many bytes `out` holds, including the terminator.
private func write(_ text: String, into out: UnsafeMutablePointer<CChar>?, capacity: Int) {
    guard let out, capacity > 0 else { return }

    out[0] = 0

    // Measured in UTF-8 bytes rather than in characters, because that is what
    // the buffer holds and a product name can carry more than ASCII.
    let bytes = Array(text.utf8)
    guard bytes.count < capacity else { return }

    for (index, byte) in bytes.enumerated() { out[index] = CChar(bitPattern: byte) }
    out[bytes.count] = 0
}

/// A C string as Swift sees it, and an empty one for NULL.
private func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

@_cdecl("pa_product_name")
public func pa_product_name(_ manufacturer: UnsafePointer<CChar>?,
                            _ model: UnsafePointer<CChar>?,
                            _ out: UnsafeMutablePointer<CChar>?,
                            _ capacity: Int) {
    let name = DeviceAppearance.productName(manufacturer: string(manufacturer), model: string(model))
    write(name, into: out, capacity: capacity)
}

@_cdecl("pa_symbol_name")
public func pa_symbol_name(_ manufacturer: UnsafePointer<CChar>?,
                           _ model: UnsafePointer<CChar>?,
                           _ out: UnsafeMutablePointer<CChar>?,
                           _ capacity: Int) {
    let name = DeviceAppearance.symbolName(manufacturer: string(manufacturer), model: string(model))
    write(name, into: out, capacity: capacity)
}

@_cdecl("pa_pair_symbol_name")
public func pa_pair_symbol_name(_ manufacturer: UnsafePointer<CChar>?,
                                _ model: UnsafePointer<CChar>?,
                                _ out: UnsafeMutablePointer<CChar>?,
                                _ capacity: Int) {
    let name = DeviceAppearance.pairSymbolName(manufacturer: string(manufacturer), model: string(model))
    write(name, into: out, capacity: capacity)
}
