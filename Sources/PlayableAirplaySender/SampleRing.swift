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
        samples.withUnsafeBufferPointer { write($0) }
    }

    /**
     Writes samples from a buffer the caller already holds, or none of them.

     The route an audio callback takes, and the reason this overload is the one
     the rest of the write path is built on rather than the other way round. The
     samples are copied from where they already are straight into the storage,
     so nothing between the callback and this copy allocates, and a heap
     allocation is the one thing a thread with a deadline cannot afford.

     All or nothing, for the same reason as above.

     @param samples What to write.
     @returns Whether they were written.
     */
    func write(_ samples: UnsafeBufferPointer<Int16>) -> Bool {
        // Nothing to write is written, which is what the storage already holds.
        // It leaves before the indices move, because a ring of no capacity has
        // no remainder to take one modulo.
        guard let source = samples.baseAddress, !samples.isEmpty else { return true }

        lock.lock()
        defer { lock.unlock() }

        guard samples.count <= capacity - count else { return false }

        // In two pieces where the write reaches the end of the storage and
        // carries on at the front of it, which is the whole of what makes this
        // a ring.
        let untilTheEnd = min(samples.count, capacity - writeIndex)
        storage.withUnsafeMutableBufferPointer { destination in
            destination.baseAddress?.advanced(by: writeIndex).update(from: source, count: untilTheEnd)

            if untilTheEnd < samples.count {
                destination.baseAddress?.update(from: source.advanced(by: untilTheEnd),
                                                count: samples.count - untilTheEnd)
            }
        }

        writeIndex = (writeIndex + samples.count) % capacity
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
        // Nothing to read is read, and it leaves before the indices move,
        // because a ring of no capacity has no remainder to take one modulo.
        guard !destination.isEmpty else { return true }

        lock.lock()
        defer { lock.unlock() }

        // Taken before the buffer is borrowed, because reading the array's own
        // count inside that is a second access to something being written.
        let wanted = destination.count
        guard wanted <= count else { return false }

        // In two pieces, the same way a write goes in, rather than a sample at
        // a time. A sample at a time is a division per sample inside the lock,
        // and the lock is the one the thread carrying live audio waits on.
        let untilTheEnd = min(wanted, capacity - readIndex)
        let from = readIndex

        storage.withUnsafeBufferPointer { source in
            destination.withUnsafeMutableBufferPointer { target in
                guard let stored = source.baseAddress, let into = target.baseAddress else { return }

                into.update(from: stored.advanced(by: from), count: untilTheEnd)

                if untilTheEnd < wanted {
                    into.advanced(by: untilTheEnd).update(from: stored, count: wanted - untilTheEnd)
                }
            }
        }

        readIndex = (readIndex + wanted) % capacity
        count -= wanted

        return true
    }

    /// How many samples are waiting, which is how far ahead of the speaker the source has run.
    var held: Int {
        lock.lock()
        defer { lock.unlock() }

        return count
    }

    /**
     Throws away everything in it and says how much that was.

     Which ending a session does, and changing source does. One acquisition
     rather than two: asking what it holds and then emptying it lets the sending
     thread take a packet in between, so the figure a caller is handed is out by
     up to a packet's worth of audio. That figure is only ever reported, so this
     is not worth a lock of its own, and doing it in one is free.

     @returns How many samples were thrown away.
     */
    @discardableResult
    func drain() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let held = count

        readIndex = 0
        writeIndex = 0
        count = 0

        return held
    }
}
