//
//  CAppearance.swift
//  Naming and drawing a device, seen from C.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// Copies a Swift string into a C buffer, cutting it short rather than overrunning.
///
/// A short buffer gives a short name. Writing nothing instead would be
/// indistinguishable from a device that published no name at all, which is what
/// an empty buffer means everywhere else here, so a caller with forty bytes of
/// name and thirty-two bytes of room would read the device as nameless.
/// `copyString` in the discovery has always truncated, and this is the same
/// answer for the same reason.
///
/// - Parameters:
///   - text: What to write.
///   - out: Where to write it, or nil to ask how much room it would need.
///   - capacity: How many bytes `out` holds, including the terminator.
/// - Returns: How many bytes the whole name needs, not counting the terminator,
///   so a caller that was cut short can make room for `capacity` of that plus
///   one and ask again. Answered whether or not anything was written.
@discardableResult
func writeCString(_ text: String, into out: UnsafeMutablePointer<CChar>?, capacity: Int) -> Int {
    // Measured in UTF-8 bytes rather than in characters, because that is what
    // the buffer holds and a product name can carry more than ASCII.
    let bytes = Array(text.utf8)

    guard let out, capacity > 0 else { return bytes.count }

    let room = capacity - 1
    let taken = bytes.count <= room ? bytes.count : lastBoundary(atOrBefore: room, in: bytes)

    for index in 0..<taken { out[index] = CChar(bitPattern: bytes[index]) }
    out[taken] = 0

    return bytes.count
}

/// Where the UTF-8 sequence before a byte count ends, so a cut never lands inside a character.
///
/// Half a character is not a shorter name, it is a byte sequence no reader can
/// decode, and on Apple's platforms `String(cString:)` on one of those gives a
/// replacement character rather than a name.
///
/// - Parameters:
///   - limit: The most bytes there is room for.
///   - bytes: The whole name, in UTF-8.
/// - Returns: How many bytes to take, which is at most `limit`.
private func lastBoundary(atOrBefore limit: Int, in bytes: [UInt8]) -> Int {
    var cut = limit

    // A continuation byte is `10xxxxxx`, so a cut landing on one is inside a
    // character and moves back until it is not.
    while cut > 0, bytes[cut] & 0xC0 == 0x80 { cut -= 1 }

    return cut
}

/// A C string as Swift sees it, and an empty one for NULL.
private func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

@_cdecl("pa_product_name")
public func pa_product_name(_ manufacturer: UnsafePointer<CChar>?,
                            _ model: UnsafePointer<CChar>?,
                            _ out: UnsafeMutablePointer<CChar>?,
                            _ capacity: Int) -> Int {
    let name = DeviceAppearance.productName(manufacturer: string(manufacturer), model: string(model))

    return writeCString(name, into: out, capacity: capacity)
}

@_cdecl("pa_symbol_name")
public func pa_symbol_name(_ manufacturer: UnsafePointer<CChar>?,
                           _ model: UnsafePointer<CChar>?,
                           _ out: UnsafeMutablePointer<CChar>?,
                           _ capacity: Int) -> Int {
    let name = DeviceAppearance.symbolName(manufacturer: string(manufacturer), model: string(model))

    return writeCString(name, into: out, capacity: capacity)
}

@_cdecl("pa_pair_symbol_name")
public func pa_pair_symbol_name(_ manufacturer: UnsafePointer<CChar>?,
                                _ model: UnsafePointer<CChar>?,
                                _ out: UnsafeMutablePointer<CChar>?,
                                _ capacity: Int) -> Int {
    let name = DeviceAppearance.pairSymbolName(manufacturer: string(manufacturer), model: string(model))

    return writeCString(name, into: out, capacity: capacity)
}
