// swift-tools-version: 5.9
//
//  Package.swift
//  Everything this needs is built here, so adding the package to a project is
//  the whole of the work. Mbed TLS, ed25519 and the C++ sender are targets of
//  their own, and nothing about them reaches the Swift interface.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import PackageDescription

/// Where the Mbed TLS checkout keeps things that are not its library.
let mbedTLSExtras = [
    "3rdparty", "ChangeLog.d", "cmake", "configs", "docs", "doxygen", "framework",
    "pkgconfig", "programs", "scripts", "tests", "visualc",
    "BRANCHES.md", "BUGS.md", "ChangeLog", "CMakeLists.txt", "CONTRIBUTING.md",
    "DartConfiguration.tcl", "dco.txt", "LICENSE", "Makefile", "README.md",
    "SECURITY.md", "SUPPORT.md",
    "library/CMakeLists.txt", "library/Makefile",
]

/// Where the sender's checkout keeps things that are not the three files wanted from it.
let senderExtras = [
    "example", "licenses", "test", "third_party",
    "CHANGELOG.md", "CMakeLists.txt", "CONTRIBUTING.md", "LICENSE", "NOTICE",
    "README.md", "ROADMAP.md", "SECURITY.md",
    "src/raop_qt_host.cpp",
]

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
    ],
    targets: [
        // The Swift interface, and the only thing a caller sees.
        .target(
            name: "PlayableAirplay",
            dependencies: ["CPlayableAirplay"]
        ),

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
            path: ".",
            exclude: [
                "LICENSE", "NOTICE", "Package.swift", "README.md",
                // Named by publicHeadersPath rather than compiled.
                "Sources/CPlayableAirplay/include/module.modulemap",
                "Scripts", "Sources/Demo", "Sources/PlayableAirplay", "Tests", "Website",
                "third_party/airplay2-sender-cpp/src/raop_qt_host.cpp",
                // Every seed comes from Mbed TLS, so this file and its entropy
                // paths are left out and ED25519_NO_SEED set in their place.
                "third_party/airplay2-sender-cpp/third_party/ed25519/src/seed.c",
                "third_party/mbedtls/library/CMakeLists.txt",
                "third_party/mbedtls/library/Makefile",
            ],
            sources: [
                "Sources/CPlayableAirplay",
                "third_party/airplay2-sender-cpp/src",
                "third_party/airplay2-sender-cpp/third_party/ed25519/src",
                "third_party/mbedtls/library",
            ],
            publicHeadersPath: "Sources/CPlayableAirplay/include",
            cSettings: [
                .define("ED25519_NO_SEED"),
                .headerSearchPath("third_party/mbedtls/include"),
                .headerSearchPath("third_party/mbedtls/library"),
                .headerSearchPath("third_party/airplay2-sender-cpp/src"),
                .headerSearchPath("third_party/airplay2-sender-cpp/third_party/ed25519/src"),
            ],
            cxxSettings: [
                .headerSearchPath("third_party/mbedtls/include"),
                .headerSearchPath("third_party/airplay2-sender-cpp/src"),
                .headerSearchPath("third_party/airplay2-sender-cpp/third_party/ed25519/src"),
            ],
            linkerSettings: [
                // Bonjour. Apple's own on its platforms, Avahi's compatibility
                // library everywhere else.
                .linkedLibrary("dns_sd", .when(platforms: [.linux])),
            ]
        ),

        // Finds receivers, plays a tone, and plays a file, from a terminal.
        .executableTarget(
            name: "Demo",
            dependencies: ["PlayableAirplay"]
        ),

        .testTarget(
            name: "PlayableAirplayTests",
            dependencies: ["PlayableAirplay", "CPlayableAirplay"]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
