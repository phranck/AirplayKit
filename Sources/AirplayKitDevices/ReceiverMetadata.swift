//
//  ReceiverMetadata.swift
//  Product names from AirPlay and standard UPnP descriptions.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

package enum ReceiverMetadata {
    /// A description belongs to the host that sent the SSDP reply. A foreign
    /// LOCATION cannot silently relabel another AirPlay receiver.
    static func location(in response: Data, from sourceAddress: String) -> URL? {
        guard response.count <= 8_192,
              let text = String(data: response, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first?.hasPrefix("HTTP/1.1 200 ") == true else { return nil }

        var location: String?
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "location" {
                location = String(line[line.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard let location, let parts = URLComponents(string: location),
              parts.scheme?.lowercased() == "http", parts.user == nil, parts.password == nil,
              parts.host?.lowercased() == sourceAddress.lowercased(),
              let url = parts.url else { return nil }
        return url
    }

    /// Only the root device's model is the advertised receiver. UPnP descriptions
    /// may contain nested renderer and server devices with their own modelName.
    static func modelName(in description: Data) -> String? {
        guard description.count <= 262_144 else { return nil }
        let reader = RootDeviceModelReader()
        let parser = XMLParser(data: description)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { return nil }
        let name = reader.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The unauthenticated AirPlay info reply can supply the manufacturer while
    /// Bonjour has reported only the RAOP half of a receiver's description.
    static func airPlayName(in response: Data, manufacturer: String, model: String) -> String? {
        guard response.count <= 262_144,
              let info = try? PropertyListSerialization.propertyList(from: response,
                                                                    format: nil) as? [String: Any]
        else { return nil }
        let reportedManufacturer = info["manufacturer"] as? String ?? manufacturer
        let reportedModel = info["model"] as? String ?? model
        let name = DeviceAppearance.productName(manufacturer: reportedManufacturer,
                                                model: reportedModel)
        return name.isEmpty ? nil : name
    }

    static func preferredName(upnp: Data?, airPlayInfo: Data?,
                              manufacturer: String, model: String) -> String {
        if let upnp, let name = modelName(in: upnp) { return name }
        if let airPlayInfo,
           let name = airPlayName(in: airPlayInfo, manufacturer: manufacturer, model: model) {
            return name
        }
        return DeviceAppearance.productName(manufacturer: manufacturer, model: model)
    }
}

private final class RootDeviceModelReader: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var captured = ""
    var modelName = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        path.append(elementName.components(separatedBy: ":").last ?? elementName)
        if path == ["root", "device", "modelName"] { captured = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path == ["root", "device", "modelName"] { captured += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if path == ["root", "device", "modelName"] { modelName = captured }
        if !path.isEmpty { path.removeLast() }
    }
}
