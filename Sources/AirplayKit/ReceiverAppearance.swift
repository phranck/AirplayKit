//
//  ReceiverAppearance.swift
//  What a receiver is called, and what it should be drawn as.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
import AirplayKitDevices

public extension AirPlayReceiver {
    /// What kind of thing this is.
    ///
    /// Apple's receivers publish no manufacturer and put an identifier in
    /// ``model``, so the identifier's family says what they are. Everybody else
    /// publishes a manufacturer, and nothing they publish says what shape the
    /// thing is, so they are all `DeviceKind.speaker`.
    ///
    /// A receiver whose ``AirPlayReceiver/isFullyDescribed`` is false has not
    /// published a manufacturer yet rather than published none, so this answers
    /// from its identifier alone. Apple's hardware is still recognised, because
    /// its identifier says so by itself, and everybody else's is
    /// `DeviceKind.unknown` until the rest of the record arrives.
    var kind: Kind {
        switch DeviceAppearance.kind(manufacturer: manufacturer, model: model) {
        case .homePod: return .homePod
        case .homePodMini: return .homePodMini
        case .appleTV: return .appleTV
        case .mac: return .mac
        case .speaker: return .speaker
        case .unknown: return .unknown
        }
    }

    /// What to call this on screen, under the name its owner gave it.
    ///
    /// "Sonos One" for a receiver that publishes a manufacturer, which is the
    /// two fields joined, and "HomePod mini" for one of Apple's, whose
    /// identifier is turned into a name from a table the package carries.
    ///
    /// That table is copied out of macOS rather than asked of it, so macOS and
    /// Linux answer identically, and because the identifier alone does not say
    /// what a machine is: a `Mac16,12` is a MacBook Air and a `Mac16,11` is a
    /// Mac mini. A model newer than the table falls back to its family, so an
    /// unknown Apple TV is "Apple TV" rather than nothing.
    ///
    /// An empty string where nothing was published, which a caller shows as
    /// nothing rather than as "unknown".
    ///
    /// This is what is known at the moment it is read. A receiver whose
    /// ``AirPlayReceiver/isFullyDescribed`` is false answers from half a record,
    /// so a Sonos may read as "One" here and as "Sonos One" once the rest has
    /// arrived. ``resolveProductName()`` can read a fuller model independently
    /// of whether that second Bonjour record arrives.
    var productName: String {
        DeviceAppearance.productName(manufacturer: manufacturer, model: model)
    }

    /// Reads a fuller product name when the receiver publishes a standard UPnP
    /// device description. If it does not, the AirPlay `/info` response may
    /// complete the Bonjour fields. The published product name remains the
    /// fallback, so a receiver without either endpoint stays visible.
    ///
    /// This performs network requests and should be called when the receiver
    /// appears, rather than while constructing a view row.
    func resolveProductName() async -> String {
        await ReceiverMetadataResolver.shared.productName(host: host,
                                                           manufacturer: manufacturer,
                                                           model: model)
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
        DeviceAppearance.symbolName(manufacturer: manufacturer, model: model)
    }

    /// The SF Symbol for a pair of these playing as one, such as a stereo set.
    ///
    /// A caller that knows two receivers are bonded draws the pair rather than
    /// one of them. Nothing in the service record says a pair is a pair, so
    /// this is offered rather than chosen here.
    var pairSymbolName: String {
        DeviceAppearance.pairSymbolName(manufacturer: manufacturer, model: model)
    }
}
