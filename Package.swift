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
    platforms: [.macOS(.v12)],
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

    ],
    dependencies: [
        /*
         The cryptography AirPlay 2 needs, on macOS and Linux
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

         This is the implementation beneath the Swift and C products. It is
         package-scoped: callers use the two products above rather than its
         pairing, timing and transport types directly.
         */
        .target(
            name: "PlayableAirplaySender",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "BigInt", package: "BigInt"),
            ]
        ),

        /*
         What a device is called and what to draw it as.

         Its own target, and the lowest Swift one, because the C interface has
         to reach it. An Objective-C application takes the C library and gets
         everything through the header, and that header cannot promise
         something declared above it: CPlayableAirplay sits under the Swift
         library that knows about receivers, and the reverse would be a cycle.

         Uses Foundation for AirPlay metadata and standard UPnP device descriptions.
         It has no package dependency of its own.

         Not a product. The Swift library hands it on as properties of a
         receiver, and C hands it on through the header.
         */
        .target(name: "PlayableAirplayDevices"),

        /*
         The C discovery boundary.

         The public C header and the discovery implementation. The session
         entry points are exported by the Swift sender through @_cdecl, and
         the device naming entry points come from PlayableAirplayDevices.
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
            dependencies: ["PlayableAirplay", "PlayableAirplaySender"]
        ),

        .testTarget(
            name: "PlayableAirplayTests",
            dependencies: ["PlayableAirplay", "CPlayableAirplay",
                           "PlayableAirplayDevices", "PlayableAirplaySender"]
        ),

        .testTarget(
            name: "PlayableAirplaySenderTests",
            dependencies: ["PlayableAirplaySender"]
        ),
    ]
)
