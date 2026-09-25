//
//  HomeKitTLV.swift
//  The encoding every pairing message is carried in.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 The items a pairing message is built from.

 HomeKit numbers them, and a receiver reads them by number rather than by
 position, so a message is a set of these rather than a sequence. Only the ones
 transient pairing uses are named here; a number that arrives without a name is
 kept as it is rather than dropped, because a message carrying something
 unexpected is still a message worth reading.
 */
package enum HomeKitTLVType: UInt8, Sendable {
    case method = 0x00
    case identifier = 0x01
    case salt = 0x02
    case publicKey = 0x03
    case proof = 0x04
    case encryptedData = 0x05
    case state = 0x06
    case error = 0x07
    case signature = 0x0A
    case flags = 0x13
}

/**
 One item of a pairing message: a type, and the bytes under it.

 Held as a pair rather than as a dictionary because a message may carry the same
 type twice, and because the order items arrive in is the order they are written
 back.

 @property type The number the receiver reads the item by.
 @property value The bytes under it, of any length, including none.
 */
package struct HomeKitTLVItem: Equatable, Sendable {
    public let type: UInt8
    public let value: Data

    public init(type: UInt8, value: Data) {
        self.type = type
        self.value = value
    }

    public init(_ type: HomeKitTLVType, _ value: Data) {
        self.init(type: type.rawValue, value: value)
    }
}

/**
 Reads and writes the HomeKit TLV8 encoding.

 Each item is a type byte, a length byte, and that many bytes of value. A value
 longer than 255 bytes cannot say so in one byte, so it is written as several
 consecutive items of the same type, and a reader joins them back together. That
 is not an edge case here: a 3072-bit SRP public key is 384 bytes and is split
 every time.
 */
package enum HomeKitTLV {
    /// What one item's length field can express, and therefore where a value is split.
    static let maximumItemLength = 255

    /**
     Writes items into their wire form.

     Splits any value longer than `maximumItemLength` into consecutive items of
     the same type, which is how the format carries a long value at all.

     @param items The items to write, in the order they should appear.
     @returns The encoded bytes.
     */
    public static func encode(_ items: [HomeKitTLVItem]) -> Data {
        var out = Data()

        for item in items {
            var remaining = item.value[...]

            // A value of no length is still an item, and saying so is sometimes
            // the whole message, so this runs at least once.
            repeat {
                let chunk = remaining.prefix(maximumItemLength)
                out.append(item.type)
                out.append(UInt8(chunk.count))
                out.append(contentsOf: chunk)
                remaining = remaining.dropFirst(chunk.count)
            } while !remaining.isEmpty
        }

        return out
    }

    /**
     Reads items back out of their wire form.

     Consecutive items of the same type are joined, so a caller sees the value a
     writer meant rather than the fragments the format required.

     @param data The bytes as they arrived.
     @returns The items in the order they appeared, or nil where the bytes run
     out in the middle of one, which means the message is truncated rather than
     merely unfamiliar.
     */
    public static func decode(_ data: Data) -> [HomeKitTLVItem]? {
        var items: [HomeKitTLVItem] = []
        var index = data.startIndex

        while index < data.endIndex {
            guard data.index(index, offsetBy: 1) < data.endIndex else { return nil }

            let type = data[index]
            let length = Int(data[data.index(index, offsetBy: 1)])
            let valueStart = data.index(index, offsetBy: 2)

            guard let valueEnd = data.index(valueStart, offsetBy: length, limitedBy: data.endIndex),
                  valueEnd <= data.endIndex
            else { return nil }

            let value = Data(data[valueStart..<valueEnd])

            // A value that was split across several items is put back together,
            // which is what makes the split invisible to whoever reads this.
            //
            // A split is recognised by the item before it having been filled to
            // the length byte's limit, because that is the only reason a writer
            // would have started another. An empty item satisfies the remainder
            // as well and is not one: it is a whole item that says nothing, and
            // joining it to what follows would lose it.
            if let last = items.last, last.type == type, Self.continues(after: last.value) {
                items[items.count - 1] = HomeKitTLVItem(type: type, value: last.value + value)
            }
            else {
                items.append(HomeKitTLVItem(type: type, value: value))
            }

            index = valueEnd
        }

        return items
    }

    /**
     Whether an item of this size is one a writer would have carried on from.

     A writer starts another item only because the length byte ran out, so a
     value that filled it exactly is the one case where more of the same type
     belongs to it. Everything shorter is a whole item, and that includes an
     item of no length at all, which is what a separator or a repeated empty
     field is in this encoding.

     @param value What the item before this one held, after any earlier joining.
     */
    static func continues(after value: Data) -> Bool {
        !value.isEmpty && value.count % maximumItemLength == 0
    }
}

package extension Array where Element == HomeKitTLVItem {
    /**
     The value under a type, or nil where the message does not carry it.

     @param type The type to look for.
     @returns The first value of that type, joined where it was split.
     */
    func value(for type: HomeKitTLVType) -> Data? {
        first { $0.type == type.rawValue }?.value
    }
}
