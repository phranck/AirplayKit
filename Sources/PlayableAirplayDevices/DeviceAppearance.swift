//
//  DeviceAppearance.swift
//  What a device is called, and what it should be drawn as.
//
//  Apart from the rest of the library on purpose. An Objective-C application
//  takes the C library and reaches everything through the header, and the C
//  target sits below the Swift one that knows about receivers, so anything the
//  header promises has to live here or lower. Putting it here is also what
//  keeps one answer: the Swift face and the C face read the same code rather
//  than each working it out.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/// What kind of thing a device is, as far as what it publishes says.
///
/// Enough to pick a picture for it and no more.
public enum DeviceKind: String, Sendable {
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

/// Naming and drawing a device from the two fields that say what it is.
///
/// Everybody but Apple publishes a manufacturer, so "Sonos One" is the two
/// fields joined. Apple publishes none and puts an identifier in the model
/// instead, and that absence is what tells the two cases apart without a table
/// of identifiers.
public enum DeviceAppearance {
    /**
     What kind of thing this is.

     - Parameters:
       - manufacturer: What it published, or empty for Apple's.
       - model: Its model or identifier.
     */
    public static func kind(manufacturer: String, model: String) -> DeviceKind {
        guard manufacturer.isEmpty else { return .speaker }

        // Apple's own families. The part before the comma is the family and the
        // part after it is the generation, and only the family is needed here.
        if model.hasPrefix("AudioAccessory") {
            return isMini(model) ? .homePodMini : .homePod
        }

        if model.hasPrefix("AppleTV") { return .appleTV }
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return .mac }

        return .unknown
    }

    /**
     What to call this on screen, under the name its owner gave it.

     "Sonos One" for a device that publishes a manufacturer, and "HomePod mini"
     for one of Apple's, whose identifier is turned into a name from the table
     the package carries.

     That table is copied out of macOS rather than asked of it, so both
     platforms answer the same way, and because the identifier alone does not
     carry the product: a `Mac16,11` is a Mac mini and a `Mac16,12` is a MacBook
     Air. An identifier newer than the table falls back to its family.

     - Returns: The name, or an empty string where nothing was published, which
       a caller shows as nothing rather than as "unknown".
     */
    public static func productName(manufacturer: String, model: String) -> String {
        if !manufacturer.isEmpty {
            return model.isEmpty ? manufacturer : "\(manufacturer) \(model)"
        }

        guard !model.isEmpty else { return "" }

        return DeviceModelNames.name(for: model) ?? familyName(for: model)
    }

    /**
     The SF Symbol that draws this, such as `hifispeaker`.

     A name rather than an image, so this is the same on both platforms and
     nothing here depends on a framework. On Apple platforms a caller hands it
     to the system; elsewhere it is a string to map to whatever it draws with.

     Apple's hardware is drawn as itself, because the symbol catalogue has one
     shaped like each of them. Everybody else's is drawn as a speaker, because
     the catalogue has nothing shaped like a Sonos and no soundbar at all.
     */
    public static func symbolName(manufacturer: String, model: String) -> String {
        switch kind(manufacturer: manufacturer, model: model) {
        case .homePod: return "homepod.fill"
        case .homePodMini: return "homepod.mini.fill"
        case .appleTV: return "appletv.fill"
        case .mac: return macSymbolName(for: productName(manufacturer: manufacturer, model: model))
        case .speaker, .unknown: return "hifispeaker.fill"
        }
    }

    /**
     The SF Symbol for two of these playing as one, such as a stereo set.

     For a caller that knows two devices are bonded. Nothing a device publishes
     says a pair is a pair, so this is offered rather than chosen here.
     */
    public static func pairSymbolName(manufacturer: String, model: String) -> String {
        switch kind(manufacturer: manufacturer, model: model) {
        case .homePod: return "homepod.2.fill"
        case .homePodMini: return "homepod.mini.2.fill"
        case .appleTV, .mac: return symbolName(manufacturer: manufacturer, model: model)
        case .speaker, .unknown: return "hifispeaker.2.fill"
        }
    }

    // MARK: - Working it out

    /// Whether an `AudioAccessory` identifier names the mini.
    ///
    /// `AudioAccessory5,x` is the mini and the others are full sized, which was
    /// read out of the system's own answer for each identifier rather than
    /// remembered.
    static func isMini(_ model: String) -> Bool {
        model.dropFirst("AudioAccessory".count).prefix { $0.isNumber } == "5"
    }

    /// As much as an identifier says on its own, which is the family.
    ///
    /// The fallback for a model the table does not carry. It is deliberately
    /// short of the exact product, because the exact product is not in the
    /// identifier: Apple's current Macs all read `Mac16,x`, and the number
    /// after the comma is the only thing that separates a MacBook Air from a
    /// Mac mini.
    static func familyName(for model: String) -> String {
        if model.hasPrefix("AudioAccessory") { return isMini(model) ? "HomePod mini" : "HomePod" }
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
    ///
    /// Filled wherever a filled one exists. The two computers are the
    /// exception: the catalogue carries no `laptopcomputer.fill` and no
    /// `desktopcomputer.fill`, which was read out of it rather than assumed.
    static func macSymbolName(for name: String) -> String {
        if name.contains("MacBook") { return "laptopcomputer" }
        if name.contains("mini") { return "macmini.gen3.fill" }
        if name.contains("Studio") { return "macstudio.fill" }
        if name.contains("Pro") { return "macpro.gen3.fill" }

        return "desktopcomputer"
    }
}

/// What one of Apple's model identifiers means, asked without a device.
///
/// A caller drawing a list of destinations has the machine it is running on in
/// it as well as the receivers, and that machine is not a receiver: it arrives
/// as an identifier out of `sysctl` rather than out of a service record.
public enum AppleDevice {
    /// What Apple calls a model identifier, such as "MacBook Air" for `Mac16,12`.
    ///
    /// - Returns: The name, or the family where the table does not carry the
    ///   identifier, or nil where it is not one of Apple's at all.
    public static func productName(for identifier: String) -> String? {
        guard !identifier.isEmpty else { return nil }

        let name = DeviceAppearance.productName(manufacturer: "", model: identifier)

        return name == identifier ? nil : name
    }

    /// The SF Symbol that draws a model identifier.
    ///
    /// - Returns: The symbol name, or nil where the identifier is not one of
    ///   Apple's, which a caller draws as whatever it uses for a stranger.
    public static func symbolName(for identifier: String) -> String? {
        guard productName(for: identifier) != nil else { return nil }

        return DeviceAppearance.symbolName(manufacturer: "", model: identifier)
    }
}
