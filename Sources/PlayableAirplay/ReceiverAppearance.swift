//
//  ReceiverAppearance.swift
//  What a receiver is called, and what it should be drawn as.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

public extension AirPlayReceiver {
    /// What kind of thing a receiver is, as far as what it publishes says.
    ///
    /// Enough to pick a picture for it and no more. A list draws a receiver by
    /// what it is, and everything below is worked out from the service record
    /// without asking the device anything.
    enum Kind: String, Sendable {
        /// A HomePod of the full size.
        case homePod

        /// A HomePod mini.
        case homePodMini

        /// An Apple TV.
        case appleTV

        /// A Mac.
        case mac

        /// Somebody else's speaker, which is everything that publishes a manufacturer.
        case speaker

        /// Nothing said what it is.
        case unknown
    }

    /// What kind of thing this is.
    ///
    /// Apple's receivers publish no manufacturer and put an identifier in
    /// ``model``, so the identifier's family says what they are. Everybody else
    /// publishes a manufacturer, and nothing they publish says what shape the
    /// thing is, so they are all ``Kind/speaker``.
    var kind: Kind {
        guard manufacturer.isEmpty else { return .speaker }

        // Apple's own families. The part before the comma is the family and the
        // part after it is the generation, and only the family is needed here.
        if model.hasPrefix("AudioAccessory") {
            return Self.homePodFamily(model) == .mini ? .homePodMini : .homePod
        }

        if model.hasPrefix("AppleTV") { return .appleTV }
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return .mac }

        return .unknown
    }

    /// What to call this on screen, under the name its owner gave it.
    ///
    /// "Sonos One" for a receiver that publishes a manufacturer, which is the
    /// two fields joined, and "HomePod mini" for one of Apple's, which is the
    /// identifier turned into a name.
    ///
    /// The name for an identifier comes from a table copied out of macOS, which
    /// files every model it knows under its identifier and gives the name it
    /// sells the thing under. It is carried here rather than asked of the
    /// system, so macOS and Linux answer identically, and because the
    /// identifier alone does not say what a machine is: a `Mac16,12` is a
    /// MacBook Air and a `Mac16,11` is a Mac mini.
    ///
    /// A model newer than that table falls back to its family, so an unknown
    /// `AppleTV` is "Apple TV" rather than nothing.
    ///
    /// An empty string where nothing was published, which a caller shows as
    /// nothing rather than as "unknown".
    var productName: String {
        if !manufacturer.isEmpty {
            return model.isEmpty ? manufacturer : "\(manufacturer) \(model)"
        }

        guard !model.isEmpty else { return "" }

        return Self.knownName(for: model) ?? Self.familyName(for: model)
    }

    /// The SF Symbol that draws this, such as `hifispeaker`.
    ///
    /// A name rather than an image, so this stays the same on both platforms
    /// and nothing here depends on a framework. On Apple platforms it is a
    /// symbol the system draws; elsewhere it is a string a caller maps to
    /// whatever it draws with.
    ///
    /// Apple's hardware is drawn as itself, because the catalogue has a symbol
    /// shaped like each of them. Everybody else's is drawn as a speaker,
    /// because the catalogue has nothing shaped like a Sonos and there is no
    /// soundbar in it at all.
    var symbolName: String {
        switch kind {
        case .homePod: return "homepod"
        case .homePodMini: return "homepod.mini"
        case .appleTV: return "appletv"
        case .mac: return Self.macSymbolName(for: productName)
        case .speaker, .unknown: return "hifispeaker"
        }
    }

    /// The SF Symbol for a pair of these playing as one, such as a stereo set.
    ///
    /// A caller that knows two receivers are bonded draws the pair rather than
    /// one of them. Nothing in the service record says a pair is a pair, so
    /// this is offered rather than chosen here.
    var pairSymbolName: String {
        switch kind {
        case .homePod: return "homepod.2"
        case .homePodMini: return "homepod.mini.2"
        case .appleTV, .mac: return symbolName
        case .speaker, .unknown: return "hifispeaker.2"
        }
    }
}

// MARK: - Working it out

// Internal rather than private, because these are the parts that can be wrong
// on their own and so are the parts worth testing on their own.
extension AirPlayReceiver {
    /// Which HomePod an `AudioAccessory` identifier names.
    enum HomePodFamily {
        case full
        case mini
    }

    /// The family, from the number before the comma.
    ///
    /// `AudioAccessory5,x` is the mini and the others are full sized, which was
    /// read out of the system's own answer for each identifier rather than
    /// remembered.
    static func homePodFamily(_ model: String) -> HomePodFamily {
        let generation = model.dropFirst("AudioAccessory".count).prefix { $0.isNumber }

        return generation == "5" ? .mini : .full
    }

    /// What Apple calls a model identifier, from the table the package carries.
    ///
    /// Copied out of macOS by `Scripts/extract-device-models` rather than asked
    /// of it, so that both platforms answer the same way. Asking the live
    /// system on macOS and falling back to a table elsewhere would be two
    /// answers to one question, and the one that could disagree is the one
    /// nobody is looking at.
    ///
    /// Nil for anything the table does not carry, which is a model newer than
    /// the macOS the table was taken from. Running the script again on a newer
    /// system is what fixes that.
    static func knownName(for model: String) -> String? {
        DeviceModelNames.name(for: model)
    }

    /// As much as the identifier says on its own, which is the family.
    ///
    /// The fallback for a model the table does not carry. It is deliberately short
    /// of the exact product, because the exact product is not in the
    /// identifier: Apple's current Macs all read `Mac16,x` and the number after
    /// the comma is the only thing that separates a MacBook Air from a Mac
    /// mini.
    static func familyName(for model: String) -> String {
        if model.hasPrefix("AudioAccessory") {
            return homePodFamily(model) == .mini ? "HomePod mini" : "HomePod"
        }

        if model.hasPrefix("AppleTV") { return "Apple TV" }
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return "Mac" }

        return model
    }

    /// Which Mac symbol to draw, from the name rather than from the identifier.
    ///
    /// The name is the stable thing. Apple's identifiers stopped saying what
    /// the machine is when they became `Mac16,x`, whilst the name it is sold
    /// under still says MacBook or mini, and that is what the catalogue has
    /// symbols for.
    static func macSymbolName(for name: String) -> String {
        if name.contains("MacBook") { return "laptopcomputer" }
        if name.contains("mini") { return "macmini.gen3" }
        if name.contains("Studio") { return "macstudio" }
        if name.contains("Pro") { return "macpro.gen3" }

        return "desktopcomputer"
    }
}
