//
//  Utility.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 10.04.2026.
//

import Foundation

enum RuntimeError: Error {
    case unknownError
}

struct Table<Element: Identifiable> where Element.ID: Comparable {
    typealias ID = Element.ID
    var elements: [ID: Element] = [:]
    private(set) var nameToID: [String: ID] = [:]
    private(set) var idToName: [ID: String] = [:]
    
    /// On a name collision the LOWEST ID wins, regardless of `Dictionary` iteration order,
    /// so the generated constants are stable between runs. `ReverseIndex` in `DogmaText` follows the same rule.
    private mutating func register(_ name: String, for id: ID) {
        idToName[id] = name
        if let existing = nameToID[name], existing < id { return }
        nameToID[name] = id
    }
    
    func indexed(by keyPath: KeyPath<Element, String>) -> Table {
        var result = self
        for (id, value) in elements {
            result.register(value[keyPath: keyPath], for: id)
        }
        return result
    }
    
    func map<T: Identifiable>(_ transform: (Element) -> T) -> Table<T> {
        var result = Table<T>()
        for (id, element) in elements {
            let newElement = transform(element)
            result.elements[newElement.id] = newElement
            if let name = idToName[id] {
                result.register(name, for: newElement.id)
            }
        }
        return result
    }
    
    /// `nameToID` is rebuilt from the survivors: if the lowest colliding ID is filtered out, the name goes to the next one.
    func filter(_ isIncluded: (Dictionary<ID, Element>.Element) -> Bool) -> Table {
        var result = Table(elements: elements.filter(isIncluded))
        for (id, name) in idToName where result.elements[id] != nil {
            result.register(name, for: id)
        }
        return result
    }
    
    mutating func append(_ name: String? = nil, _ element: Element) {
        elements[element.id] = element
        if let name {
            register(name, for: element.id)
        }
    }
    
    func index(of name: String) -> ID? {
        nameToID[name]
    }
    
    subscript(_ id: ID) -> Element? {
        elements[id]
    }

    subscript(name: String) -> Element? {
        guard let id = index(of: name) else {return nil}
        return elements[id]
    }

    mutating func update(_ name: String, _ block: (inout Element) -> Void) {
        let id = nameToID[name]!
        block(&elements[id]!)
    }
    
    mutating func update(_ id: ID, _ block: (inout Element) -> Void) {
        block(&elements[id]!)
    }
}

extension Table where Element: Decodable {
    init(contentsOf url: URL, id: KeyPath<Element, ID>) async throws {
        let decoder = JSONDecoder()
        var result = [ID: Element]()
        for try await line in url.lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            guard let data = line.data(using: .utf8) else {throw RuntimeError.unknownError}
            let object = try decoder.decode(Element.self, from: data)
            result[object[keyPath: id]] = object
        }
        elements = result
        nameToID = [:]
        idToName = [:]
    }
}

extension Table where Element == DogmaSDE.TypeInfo, ID == TypeID {
    @MainActor
    mutating func addEffect(_ effectName: String, toType typeName: String) {
        addEffect(effectName, toType: nameToID[typeName]!)
    }

    @MainActor
    mutating func addEffect(_ effectName: String, toType typeID: TypeID) {
        let effect = dogmaEffects[effectName]!
        self.elements[typeID]!.effects.append(effect)
    }

    @MainActor
    mutating func addEffect(_ effectName: String, toGroup groupName: String) {
        let effect = dogmaEffects[effectName]!
        let groupID = UInt32(groups.nameToID[groupName]!)
        for (typeID, type) in elements where type.groupID.rawValue == groupID {
            elements[typeID]!.effects.append(effect)
        }
    }

    /// Like `addEffect(_:toGroup:)`, but silently skips a group the importer has filtered out.
    @MainActor
    mutating func addEffect(_ effectName: String, toGroupIfPresent groupName: String) {
        guard groups.nameToID[groupName] != nil else {return}
        addEffect(effectName, toGroup: groupName)
    }

    @MainActor
    mutating func addEffect(_ effectName: String, toCategory categoryName: String) {
        let effect = dogmaEffects[effectName]!
        let categoryID = categories.nameToID[categoryName]!
        let groupIDs = IndexSet(groups.elements.filter{$0.value.categoryID == categoryID}.keys)
        for (typeID, type) in elements where groupIDs.contains(Int(type.groupID.rawValue)) {
            elements[typeID]!.effects.append(effect)
        }
    }

    @MainActor
    mutating func addAttribute(_ attributeName: String, _ value: Float, toType typeName: String) {
        addAttribute(attributeName, value, toType: nameToID[typeName]!)
    }
    @MainActor
    mutating func addAttribute(_ attributeName: String, _ value: Float, toType typeID: TypeID) {
        let attributeID = dogmaAttributes.nameToID[attributeName]!
        elements[typeID]!.attributes[attributeID] = value
    }
    
    @MainActor
    mutating func addAttribute(_ attributeName: String, _ value: Float, toGroup groupName: String) {
        let attributeID = dogmaAttributes.nameToID[attributeName]!
        let groupID = groups.nameToID[groupName]!
        for (typeID, type) in elements where type.groupID.rawValue == UInt32(groupID) {
            elements[typeID]!.attributes[attributeID] = value
        }
    }
}

extension String {
    func toCamelCase() -> String {
        let words = self.components(separatedBy: CharacterSet(charactersIn: " _"))
            .filter { !$0.isEmpty }
        
        guard !words.isEmpty else { return self }
        
        let first = words[0].lowercased()
        let rest = words.dropFirst().map { $0.capitalized }
        
        return first + rest.joined()
    }
}
/// `preferred` decides who gets the unsuffixed name on an identifier collision (e.g. the unpublished NPC copy
/// `♦ Sotiyo` must not take `TypeID.sotiyo` from the published type). A single preferred ID gets the clean name
/// and the rest get suffixes from 2; otherwise all are numbered from 1.
func typeExtension<ID: FixedWidthInteger, T>(of type: T.Type = T.self, from nameToID: some Sequence<(key: String, value: ID)>, preferred: (ID) -> Bool = { _ in false }) -> String where ID: FixedWidthInteger {
    let typeName = "\(T.self)"
    
    let safeNames = nameToID.map{(key: $0.key.safeSwiftIdentifier, value: [$0.value])}
    let uniqueDic = Dictionary(safeNames) { a, b in
        a + b
    }.flatMap { (key, value) -> [(key: String, value: ID)] in
        if value.count == 1 {
            return [(key, value[0])]
        }
        let winners = value.filter(preferred)
        if winners.count == 1 {
            let rest = value.filter{$0 != winners[0]}.sorted()
            return [(key, winners[0])] + rest.enumerated().map{(key: key + "\($0.offset + 2)", value: $0.element)}
        }
        else {
            return value.sorted().enumerated().map{(key: key + "\($0.offset + 1)", value: $0.element)}
        }
    }.sorted{$0.value < $1.value}
    var staticVars: [String] = []
    if uniqueDic.first?.value != 0 {
        staticVars.append("public static let none: \(typeName) = 0")
    }
    staticVars = staticVars + uniqueDic.map{"public static let \($0.key): \(typeName) = \($0.value)"}
    return """
        //
        // DogmaKit
        // SDE Version: \(version.buildNumber), \(version.releaseDate)
        //

        import DogmaModels
        
        extension \(typeName) {
            \(staticVars.joined(separator: "\n\t"))
        }
        """
}

func typeExtension<ID: RawRepresentable & Hashable>(from nameToID: [String: ID], preferred: (ID) -> Bool = { _ in false }) -> String where ID.RawValue: FixedWidthInteger {
    typeExtension(of: ID.self, from: nameToID.map{($0.key, $0.value.rawValue)}, preferred: { preferred(ID(rawValue: $0)!) })
}
extension String {
    var safeSwiftIdentifier: String {
        var s = self

        s = s.replacing(#/[ _](\p{L})/#) { match in
            match.output.1.uppercased()
        }
        
        s = s.replacing(#/[^\p{L}\p{N}_]/#, with: "")
        
        let n = s.prefix{$0.isUppercase}.count
        if n > 0 {
            s = s.prefix(n).lowercased() + s.dropFirst(n)
        }

        s = s.replacingOccurrences(of: "_", with: "")
        
        if s.isEmpty { return "unknown" }
        
        if s.first?.isNumber == true {
            s = "_" + s
        }
        return s
    }
}

extension [DogmaSDE.TypeInfo.Attribute] {
    subscript(_ id: AttributeID) -> Float? {
        get {
            self.first{$0.id == id}?.value
        }
        mutating set {
            if let newValue {
                if let index = self.firstIndex(where: {$0.id == id}) {
                    self[index].value = newValue
                }
                else {
                    self.append(.init(id: id, value: newValue))
                }
            }
            else {
                self.removeAll{$0.id == id}
            }
        }
    }
}

