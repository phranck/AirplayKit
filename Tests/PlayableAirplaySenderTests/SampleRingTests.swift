//
//  SampleRingTests.swift
//  What the two threads carrying audio share has to get right.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import XCTest
@testable import PlayableAirplaySender

final class SampleRingTests: XCTestCase {

    // MARK: - Writing and reading

    func testWhatGoesInComesOutInOrder() {
        let ring = SampleRing(capacity: 16)
        var out = [Int16](repeating: 0, count: 4)

        XCTAssertTrue(ring.write([1, 2, 3, 4]))
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [1, 2, 3, 4])
    }

    func testItWrapsWithoutLosingOrderOrContent() {
        // The point of a ring: the indices go round and nothing is ever moved.
        let ring = SampleRing(capacity: 8)
        var out = [Int16](repeating: 0, count: 6)

        XCTAssertTrue(ring.write([1, 2, 3, 4, 5, 6]))
        XCTAssertTrue(ring.read(into: &out))

        XCTAssertTrue(ring.write([7, 8, 9, 10, 11, 12]))
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [7, 8, 9, 10, 11, 12])
    }

    func testAFullRingIsToldApartFromAnEmptyOne() {
        // Two indices that meet say nothing on their own, which is why the
        // count is kept rather than derived.
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 4)

        XCTAssertTrue(ring.write([1, 2, 3, 4]))
        XCTAssertEqual(ring.available, 0)
        XCTAssertFalse(ring.write([5]))

        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(ring.available, 4)
        XCTAssertFalse(ring.read(into: &out))
    }

    // MARK: - All or nothing

    func testAWriteThatWouldNotFitTakesNothing() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 2)

        XCTAssertTrue(ring.write([1, 2]))
        XCTAssertFalse(ring.write([3, 4, 5]))

        // Half a packet arrives as a click rather than as a gap, so a refused
        // write must leave the ring exactly as it was.
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [1, 2])
    }

    func testAReadThatCrossesTheEndComesBackInOrder() {
        // The read goes in two pieces now, the same way a write does, so the
        // join between them is where a wrong length would show. The first read
        // leaves the index part way along, and the second one steps over the
        // end of the storage.
        let ring = SampleRing(capacity: 6)
        var first = [Int16](repeating: 0, count: 4)
        var second = [Int16](repeating: 0, count: 4)

        XCTAssertTrue(ring.write([1, 2, 3, 4]))
        XCTAssertTrue(ring.read(into: &first))
        XCTAssertEqual(first, [1, 2, 3, 4])

        XCTAssertTrue(ring.write([5, 6, 7, 8]))
        XCTAssertTrue(ring.read(into: &second))
        XCTAssertEqual(second, [5, 6, 7, 8])
    }

    func testAReadOfNothingTakesNothingAndSaysSo() {
        let ring = SampleRing(capacity: 4)
        var nothing: [Int16] = []

        XCTAssertTrue(ring.write([1, 2]))
        XCTAssertTrue(ring.read(into: &nothing))
        XCTAssertEqual(ring.held, 2)
    }

    func testAReadWithTooLittleInItTakesNothing() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 3)

        XCTAssertTrue(ring.write([1, 2]))
        XCTAssertFalse(ring.read(into: &out))

        var smaller = [Int16](repeating: 0, count: 2)
        XCTAssertTrue(ring.read(into: &smaller))
        XCTAssertEqual(smaller, [1, 2])
    }

    func testDrainingSaysHowMuchItThrewAway() {
        // One acquisition rather than two. Asking what it holds and then
        // emptying it lets the sender take a packet in between, and the figure
        // a caller is handed is then short by that much.
        let ring = SampleRing(capacity: 8)

        XCTAssertEqual(ring.drain(), 0)

        XCTAssertTrue(ring.write([1, 2, 3, 4, 5]))
        XCTAssertEqual(ring.drain(), 5)
        XCTAssertEqual(ring.held, 0)
        XCTAssertEqual(ring.available, 8)
    }

    func testDrainingAfterAWrapSaysWhatWasStillInIt() {
        // The count is kept rather than derived from the two indices, so the
        // wrap is where a derived one would answer wrongly.
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 3)

        XCTAssertTrue(ring.write([1, 2, 3]))
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertTrue(ring.write([4, 5, 6]))

        XCTAssertEqual(ring.drain(), 3)
    }

    func testClearingEmptiesIt() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 2)

        XCTAssertTrue(ring.write([1, 2]))
        ring.drain()

        XCTAssertEqual(ring.available, 4)
        XCTAssertFalse(ring.read(into: &out))
    }

    func testWhatItHoldsIsWhatHasBeenWrittenAndNotYetRead() {
        // How far ahead of the speaker the source has run, which is the latency
        // a listener notices when the source changes.
        let ring = SampleRing(capacity: 8)
        var out = [Int16](repeating: 0, count: 2)

        XCTAssertEqual(ring.held, 0)

        XCTAssertTrue(ring.write([1, 2, 3, 4]))
        XCTAssertEqual(ring.held, 4)

        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(ring.held, 2)

        ring.drain()
        XCTAssertEqual(ring.held, 0)
    }

    func testWhatItHoldsIsRightAfterAWrap() {
        // The count is kept rather than derived from the two indices, so the
        // wrap is where a derived one would go wrong.
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 3)

        XCTAssertTrue(ring.write([1, 2, 3]))
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertTrue(ring.write([4, 5, 6]))

        XCTAssertEqual(ring.held, 3)
    }

    // MARK: - Writing from a pointer

    /// Writes through the overload an audio callback uses, which takes the samples where they lie.
    private func write(_ samples: [Int16], into ring: SampleRing) -> Bool {
        samples.withUnsafeBufferPointer { ring.write($0) }
    }

    func testAPointerWriteWrapsWithoutLosingOrderOrContent() {
        // The copy goes in two pieces where it reaches the end of the storage,
        // and a wrong length on either of them is heard rather than reported.
        let ring = SampleRing(capacity: 8)
        var out = [Int16](repeating: 0, count: 6)

        XCTAssertTrue(write([1, 2, 3, 4, 5, 6], into: ring))
        XCTAssertTrue(ring.read(into: &out))

        XCTAssertTrue(write([7, 8, 9, 10, 11, 12], into: ring))
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [7, 8, 9, 10, 11, 12])
    }

    func testAPointerWriteThatWouldNotFitTakesNothing() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 2)

        XCTAssertTrue(write([1, 2], into: ring))
        XCTAssertFalse(write([3, 4, 5], into: ring))

        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [1, 2])
        XCTAssertEqual(ring.held, 0)
    }

    func testBothRoutesLeaveTheSameRing() {
        // The array overload borrows a pointer from its array rather than the
        // other way round, so there is one copy into the storage and both ways
        // in reach it.
        let throughPointer = SampleRing(capacity: 8)
        let throughArray = SampleRing(capacity: 8)
        var fromPointer = [Int16](repeating: 0, count: 5)
        var fromArray = [Int16](repeating: 0, count: 5)

        XCTAssertTrue(write([9, 8, 7, 6, 5], into: throughPointer))
        XCTAssertTrue(throughArray.write([9, 8, 7, 6, 5]))

        XCTAssertTrue(throughPointer.read(into: &fromPointer))
        XCTAssertTrue(throughArray.read(into: &fromArray))
        XCTAssertEqual(fromPointer, fromArray)
    }

    func testAPointerWriteOfNothingChangesNothing() {
        let ring = SampleRing(capacity: 4)

        XCTAssertTrue(write([], into: ring))
        XCTAssertEqual(ring.held, 0)
        XCTAssertEqual(ring.available, 4)
    }

    func testOnlyTheSamplesTheBufferNamesAreTaken() {
        // A session hands over a rebased slice of whatever the caller holds, so
        // anything past the end of that slice is the caller's and not this.
        let source: [Int16] = [1, 2, 3, 4, 5, 6]
        let ring = SampleRing(capacity: 8)
        var out = [Int16](repeating: 0, count: 4)

        source.withUnsafeBufferPointer { buffer in
            XCTAssertTrue(ring.write(UnsafeBufferPointer(rebasing: buffer.prefix(4))))
        }

        XCTAssertEqual(ring.held, 4)
        XCTAssertTrue(ring.read(into: &out))
        XCTAssertEqual(out, [1, 2, 3, 4])
    }

    // MARK: - Two threads

    func testAProducerAndASenderKeepEveryFrameAndItsOrder() {
        // One thread writing whilst another reads is the whole arrangement, and
        // a wrong index shows up as an out-of-order sample rather than a crash.
        // Deliberately small, so the ring fills and the producer is refused
        // often. A ring that never fills exercises neither the wrap nor the
        // refusal, which is how this test passed on one machine and failed on
        // another.
        let packet = 352 * 2
        let ring = SampleRing(capacity: packet * 3)
        let packets = 200

        let sent = expectation(description: "everything written")
        let received = expectation(description: "everything read")

        var readBack: [Int16] = []
        readBack.reserveCapacity(packets * packet)

        DispatchQueue.global().async {
            var next: Int16 = 0
            var written = 0
            while written < packets {
                var chunk = [Int16](repeating: 0, count: packet)
                var value = next
                for index in 0..<packet {
                    chunk[index] = value
                    value = value &+ 1
                }

                // The counter moves only once the ring has taken the chunk. A
                // refused write must offer the same samples again, or the
                // sequence gains a gap that looks exactly like a ring that
                // dropped a packet.
                if ring.write(chunk) {
                    next = value
                    written += 1
                }
                else { usleep(200) }
            }
            sent.fulfill()
        }

        DispatchQueue.global().async {
            var out = [Int16](repeating: 0, count: packet)
            var taken = 0
            while taken < packets {
                if ring.read(into: &out) {
                    readBack.append(contentsOf: out)
                    taken += 1
                }
                else { usleep(200) }
            }
            received.fulfill()
        }

        wait(for: [sent, received], timeout: 20)

        XCTAssertEqual(readBack.count, packets * packet)

        var expected: Int16 = 0
        for sample in readBack {
            XCTAssertEqual(sample, expected)
            expected = expected &+ 1
        }
    }
}
