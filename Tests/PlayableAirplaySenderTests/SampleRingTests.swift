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

    func testAReadWithTooLittleInItTakesNothing() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 3)

        XCTAssertTrue(ring.write([1, 2]))
        XCTAssertFalse(ring.read(into: &out))

        var smaller = [Int16](repeating: 0, count: 2)
        XCTAssertTrue(ring.read(into: &smaller))
        XCTAssertEqual(smaller, [1, 2])
    }

    func testClearingEmptiesIt() {
        let ring = SampleRing(capacity: 4)
        var out = [Int16](repeating: 0, count: 2)

        XCTAssertTrue(ring.write([1, 2]))
        ring.clear()

        XCTAssertEqual(ring.available, 4)
        XCTAssertFalse(ring.read(into: &out))
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
