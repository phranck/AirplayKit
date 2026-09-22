//
//  XMLReading.swift
//  Taking the few values that matter out of the documents a speaker answers with.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

import Foundation

// Apple's Foundation carries the XML reader and the Foundation that ships with
// Swift elsewhere puts it in a module of its own, so it is asked for by name
// where that module exists.
#if canImport(FoundationXML)
import FoundationXML
#endif

/*
 Why this is a handful of small readers rather than a model of the documents.

 A speaker answers with SOAP envelopes and a UPnP device description, and both
 carry far more than anything here wants. Modelling them would mean keeping a
 model of somebody else's document in step with it for no gain, because what is
 wanted is a dozen named values and one list.

 `XMLParser` is Foundation's own and exists on Linux too, which is why this
 reads rather than matching text. A speaker's room name is typed by a person and
 arrives escaped, and a pattern over the raw bytes would hand back the escaping.
 */

// MARK: - The first value of each named element

/// Collects the first text of each element it was asked for.
private final class FirstValueReader: NSObject, XMLParserDelegate {
    private let wanted: Set<String>
    private var current: String?
    private var buffer = ""

    private(set) var values: [String: String] = [:]

    init(wanted: Set<String>) {
        self.wanted = wanted
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard wanted.contains(name), values[name] == nil else { return }

        current = name
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters characters: String) {
        guard current != nil else { return }
        buffer += characters
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard current == name else { return }

        values[name] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        current = nil
    }
}

/// The first text of each named element, in document order.
///
/// A device description nests three devices and repeats the same element names
/// inside each of them, so the first is the outermost one, which is the speaker
/// rather than one of the services it offers.
///
/// - Parameters:
///   - names: The elements worth reading. Anything else is skipped.
///   - data: The document.
/// - Returns: What was found, keyed by element name. An element that did not
///            appear is absent rather than empty.
func firstValues(of names: Set<String>, in data: Data) -> [String: String] {
    let reader = FirstValueReader(wanted: names)
    let parser = XMLParser(data: data)
    parser.delegate = reader
    parser.parse()

    return reader.values
}

// MARK: - Groups and their members

/// Collects zone groups, their members, and the satellites bonded into each member.
///
/// The three nest: a group holds members, and a member holds satellites. So a
/// satellite belongs to whichever member is open when it arrives, and a member
/// is finished only when its own element ends.
private final class ZoneGroupReader: NSObject, XMLParserDelegate {
    private var coordinator: String?
    private var members: [SonosZoneGroup.Member] = []

    private var memberIdentifier: String?
    private var memberRoom = ""
    private var satellites: [SonosZoneGroup.Satellite] = []

    private(set) var groups: [SonosZoneGroup] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch name {
        case "ZoneGroup":
            coordinator = attributes["Coordinator"]
            members = []

        case "ZoneGroupMember":
            // A member with no identifier is one nothing can be said about.
            guard coordinator != nil, let identifier = attributes["UUID"] else { return }
            memberIdentifier = identifier
            memberRoom = attributes["ZoneName"] ?? ""
            satellites = []

        case "Satellite":
            guard memberIdentifier != nil, let identifier = attributes["UUID"] else { return }
            satellites.append(SonosZoneGroup.Satellite(identifier: identifier,
                                                       roomName: attributes["ZoneName"] ?? ""))

        default:
            return
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "ZoneGroupMember":
            guard let memberIdentifier else { return }

            members.append(SonosZoneGroup.Member(identifier: memberIdentifier,
                                                 roomName: memberRoom,
                                                 satellites: satellites))
            self.memberIdentifier = nil
            satellites = []

        case "ZoneGroup":
            guard let coordinator else { return }

            groups.append(SonosZoneGroup(coordinatorIdentifier: coordinator, members: members))
            self.coordinator = nil
            members = []

        default:
            return
        }
    }
}

/// Every zone group in a topology document.
///
/// The topology arrives twice wrapped: a SOAP envelope holds a `ZoneGroupState`
/// element whose text is itself a whole XML document, escaped. So the text is
/// taken out first and read as a document of its own.
///
/// - Parameter data: The SOAP answer to `GetZoneGroupState`.
/// - Returns: The groups, or an empty array when the answer carried none.
func readZoneGroups(in data: Data) -> [SonosZoneGroup] {
    guard let inner = firstValues(of: ["ZoneGroupState"], in: data)["ZoneGroupState"],
          let innerData = inner.data(using: .utf8) else {
        return []
    }

    let reader = ZoneGroupReader()
    let parser = XMLParser(data: innerData)
    parser.delegate = reader
    parser.parse()

    return reader.groups
}
