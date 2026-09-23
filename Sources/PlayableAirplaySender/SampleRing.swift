//
//  SampleRing.swift
//  What the two threads carrying audio share, and the only thing they share.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 A fixed ring of samples, written by whoever produces the audio and read by the
 thread that sends it.

 Fixed because the thread producing live audio must not wait, and anything that
 grows has to allocate. The storage is taken once and never taken again, both
 ends move an index, and nothing is ever shifted along.

 That is the whole point. An array drained from the front copies everything
 behind what it removed, so the cost rises with how full the buffer is, and it
 rises whilst holding the lock the producer needs. The producer then waits
 longest exactly when the sender is furthest behind, which is when waiting does
 the most harm.

 The lock is held only for the copy in or out and the two indices. It is a plain
 lock rather than a queue because both sides are threads rather than tasks, and
 because a queue hop is the thing an audio callback cannot afford.
 */
final class SampleRing {
    private var storage: [Int16]
    private let capacity: Int

    /// Where the next sample is written, and where the next one is read.
    private var writeIndex = 0
    private var readIndex = 0

    /// How many samples are in it, kept rather than derived so full and empty are not the same.
    private var count = 0

    private let lock = NSLock()

    /**
     Takes the storage.

     @param capacity How many samples it holds, which is frames times channels.
     */
    init(capacity: Int) {
        self.capacity = capacity
        self.storage = [Int16](repeating: 0, count: capacity)
    }

    /// How many samples could be written right now.
    var available: Int {
        lock.lock()
        defer { lock.unlock() }

        return capacity - count
    }

    /**
     Writes samples, or none of them.

     All or nothing, because half a packet of audio is worse than none: it
     arrives as a click rather than as a gap the sender can account for.

     @param samples What to write.
     @returns Whether they were written.
     */
    func write(_ samples: [Int16]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard samples.count <= capacity - count else { return false }

        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
        count += samples.count

        return true
    }

    /**
     Reads samples into a buffer the caller already holds.

     @param destination Where to put them, and how many is its count.
     @returns Whether there were enough to fill it. Nothing is taken when there
     were not, so a caller that wants a whole packet is never left with part of
     one.
     */
    func read(into destination: inout [Int16]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard destination.count <= count else { return false }

        for index in 0..<destination.count {
            destination[index] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= destination.count

        return true
    }

    /// How many samples are waiting, which is how far ahead of the speaker the source has run.
    var held: Int {
        lock.lock()
        defer { lock.unlock() }

        return count
    }

    /// Throws away everything in it, which ending a session does and changing source does.
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        readIndex = 0
        writeIndex = 0
        count = 0
    }
}
