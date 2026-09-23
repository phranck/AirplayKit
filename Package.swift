// swift-tools-version: 5.9
//
//  Package.swift
//  Two Swift dependencies and nothing vendored, so adding the package to a
//  project is the whole of the work and a change to one file rebuilds one file.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "PlayableAirplay",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(name: "PlayableAirplay", targets: ["PlayableAirplay"]),

        /*
         The layer underneath, offered on purpose rather than by accident.

         Swift takes the library above and has no reason to look at this. An
         Objective-C application has no Swift to import it from, and calling a C
         header is what Objective-C does with a C library, so it takes this one
         and gets the same thing a step lower down.
         */
        .library(name: "CPlayableAirplay", targets: ["CPlayableAirplay"]),

        /*
         What a speaker will say about itself when AirPlay will not.

         Kept apart on purpose. The library above is about AirPlay and says so,
         and one manufacturer's own services do not belong inside it. A caller
         that wants both takes both.
         */
        .library(name: "PlayableAirplayUPnP", targets: ["PlayableAirplayUPnP"]),
    ],
    dependencies: [
        /*
         The cryptography AirPlay 2 needs, on Apple's platforms and on Linux
         alike: X25519, Ed25519, ChaCha20-Poly1305, HKDF and SHA-512.
         */
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),

        /*
         Arbitrary-precision integers, for the one thing swift-crypto does not
         cover. Pairing is SRP-6a over a 3072-bit group, which needs modular
         exponentiation, and neither swift-crypto nor Foundation offers one.
         */
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
    ],
    targets: [
        // The Swift interface, and the only thing a caller sees.
        .target(
            name: "PlayableAirplay",
            dependencies: ["CPlayableAirplay", "PlayableAirplaySender", "PlayableAirplayDevices"]
        ),

        /*
         The sender, in Swift.

         Built beside the C++ one rather than in place of it, so there is never
         a state in which nothing plays. It takes over underneath the two faces
         above once it does, which is #31, and the C++ checkout goes with it.

         Not a product. Nothing outside this package has a reason to reach it,
         and the two libraries above stay the whole of what a caller sees.
         */
        .target(
            name: "PlayableAirplaySender",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "BigInt", package: "BigInt"),
            ]
        ),

        /*
         Reading a speaker through its own services.

         Depends on nothing, not even on the library above, because the two
         answer the same questions by different means and neither needs the
         other to do it.
         */
        .target(name: "PlayableAirplayUPnP"),

        /*
         What a device is called and what to draw it as.

         Its own target, and the lowest Swift one, because the C interface has
         to reach it. An Objective-C application takes the C library and gets
         everything through the header, and that header cannot promise
         something declared above it: CPlayableAirplay sits under the Swift
         library that knows about receivers, and the reverse would be a cycle.

         Depends on nothing. It answers from two strings and a table.

         Not a product. The Swift library hands it on as properties of a
         receiver, and C hands it on through the header.
         */
        .target(name: "PlayableAirplayDevices"),

        /*
         Everything underneath, in one target.

         The C interface, the C++ sender, ed25519 and Mbed TLS could each be a
         target of their own, and on Apple's platforms they were. On Linux they
         cannot be: SwiftPM compiles C and C++ with explicit modules there, and
         it does not hand a C++ target the modules of the C targets it depends
         on, so every include across that line fails to resolve. One target has
         no line to cross.

         That is why the path is the package root: a header search path has to
         sit inside its own target, and these headers are spread over three
         checkouts.
         */
        .target(
            name: "CPlayableAirplay",
            dependencies: ["PlayableAirplaySender", "PlayableAirplayDevices"],
            linkerSettings: [
                // Bonjour. Apple's own on its platforms, Avahi's compatibility
                // library everywhere else.
                .linkedLibrary("dns_sd", .when(platforms: [.linux])),
            ]
        ),

        // Finds receivers, plays a tone, and plays a file, from a terminal.
        .executableTarget(
            name: "Demo",
            dependencies: ["PlayableAirplay", "PlayableAirplayUPnP", "PlayableAirplaySender"]
        ),

        .testTarget(
            name: "PlayableAirplayTests",
            dependencies: ["PlayableAirplay", "CPlayableAirplay", "PlayableAirplayUPnP", "PlayableAirplayDevices"]
        ),

        .testTarget(
            name: "PlayableAirplaySenderTests",
            dependencies: ["PlayableAirplaySender"]
        ),
    ]
)
