//
//  ALACFrame.swift
//  Packing samples into the frame a receiver expects.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 One frame of Apple Lossless, carried uncompressed.

 A receiver fixes the codec at ALAC and decodes nothing else, so samples have to
 arrive in its bitstream whatever they started as. What it does not require is
 that they actually be compressed: the format has an escape that says the
 samples follow verbatim, and taking it costs nothing but the bits it saves and
 spares this package a codec.

 The bitstream is read most significant bit first. One frame is a stereo
 channel-pair element, a short run of fields that are all zero here, the escape,
 the samples, and an end tag, padded to a byte boundary.

 ```text
 3 bits   element tag, 1 for a stereo channel pair
 4 bits   unused
 12 bits  unknown
 1 bit    has an explicit frame length, 0 so the default is used
 2 bits   wasted bytes, 0
 1 bit    is not compressed, 1
 n        interleaved 16-bit samples, most significant byte first
 3 bits   end tag, 7
 ```
 */
public enum ALACFrame {
    /// How many frames one packet carries, which RAOP fixes at this and a receiver assumes.
    public static let framesPerPacket = 352

    /// How many channels, which is the only arrangement the realtime and buffered paths carry.
    public static let channelCount = 2

    /**
     Packs interleaved 16-bit stereo samples into one frame.

     @param samples Interleaved, left then right, exactly `frames * channelCount` of them.
     @param frames How many frames the samples hold.
     @returns The frame, byte aligned.
     */
    public static func packed(_ samples: [Int16], frames: Int) -> Data {
        var out = Data()
        out.reserveCapacity(frames * channelCount * 2 + 8)

        var pending: UInt8 = 0
        var filled = 0

        func put(_ value: UInt32, _ bits: Int) {
            for shift in stride(from: bits - 1, through: 0, by: -1) {
                pending = (pending << 1) | UInt8((value >> UInt32(shift)) & 1)
                filled += 1

                if filled == 8 {
                    out.append(pending)
                    pending = 0
                    filled = 0
                }
            }
        }

        put(1, 3)     // a stereo channel-pair element
        put(0, 4)     // unused
        put(0, 12)    // unknown
        put(0, 1)     // no explicit frame length, so the default one stands
        put(0, 2)     // no wasted bytes
        put(1, 1)     // not compressed, which is the escape this takes

        for index in 0..<(frames * channelCount) {
            put(UInt32(UInt16(bitPattern: samples[index])), 16)
        }

        put(7, 3)     // the end tag

        if filled > 0 {
            out.append(pending << (8 - filled))
        }

        return out
    }
}
