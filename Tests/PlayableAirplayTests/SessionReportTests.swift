//
//  SessionReportTests.swift
//  What a session did, handed over at the moment it ends.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import CPlayableAirplay
import XCTest

/**
 The report `pa_session_close` writes.

 Its layout lives in two places and cannot live in one. The header declares
 `PASessionReport` for C to read, and the Swift side writes it from
 `PlayableAirplaySender`, which is below `CPlayableAirplay` in the package and
 therefore cannot import the header that declares it.

 So the two are held together here instead. C reads these fields by offset, so
 one added on one side and not the other is read as the wrong bytes: the
 seconds come back as a packet count and nothing anywhere reports it.
 */
final class SessionReportTests: XCTestCase {

    /// Exactly what the Swift side writes: two words, two doubles, two words.
    private typealias WrittenLayout = (Int, Double, Double, Int)

    func testTheReportTheHeaderDeclaresIsTheOneTheLibraryWrites() {
        XCTAssertEqual(MemoryLayout<PASessionReport>.size, MemoryLayout<WrittenLayout>.size)
        XCTAssertEqual(MemoryLayout<PASessionReport>.stride, MemoryLayout<WrittenLayout>.stride)

        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.inventedPackets), 0)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.inventedSeconds),
                       MemoryLayout<Int>.stride)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.waitedSeconds),
                       MemoryLayout<Int>.stride + MemoryLayout<Double>.stride)
        XCTAssertEqual(MemoryLayout<PASessionReport>.offset(of: \.fellBehind),
                       MemoryLayout<Int>.stride + MemoryLayout<Double>.stride * 2)
    }

    func testTheReportSaysWhatASessionDidRatherThanHowItIsGoing() {
        // Four figures and no state. Everything in here is a total taken at the
        // end, so a caller can hold one of these after the session it describes
        // has gone, which is the whole reason it exists.
        let report = PASessionReport(inventedPackets: 7,
                                     inventedSeconds: 1.5,
                                     waitedSeconds: 2.5,
                                     fellBehind: 3)

        XCTAssertEqual(report.inventedPackets, 7)
        XCTAssertEqual(report.inventedSeconds, 1.5)
        XCTAssertEqual(report.waitedSeconds, 2.5)
        XCTAssertEqual(report.fellBehind, 3)
    }

    // `pa_session_close` itself is not called from here.
    //
    // This target sees that symbol declared twice: as the C prototype through
    // the header, and as the @_cdecl definition through PlayableAirplaySender.
    // The two spell their pointers differently, `PASession *` arriving as an
    // OpaquePointer against the UnsafeMutableRawPointer the definition takes,
    // and calling it makes the compiler reconcile them. Swift 6.1.2, which is
    // what CI builds with, aborts on that with a deserialisation failure;
    // Swift 6.4 accepts it. The difference is in the compiler rather than in
    // this package, so the call is left out rather than written against the
    // newer of the two.
    //
    // It is a limit on calling these from Swift and not on calling them from
    // C, which is the whole of what they are for. Every @_cdecl function here
    // has the same shape.
}
