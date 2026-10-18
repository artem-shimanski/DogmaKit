//
//  main.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 09.04.2026.
//

import Foundation

let args = CommandLine.arguments
guard args.count >= 4 else { exit(1) }

let inputDir = URL(filePath: args[1])
let outputFile = URL(filePath: args[2])
let filesToProcess = args.dropFirst(3)


let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
}

struct Version: Codable {
    var buildNumber: Int
    var releaseDate: String
}

enum JSONValue: Decodable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let val = try? container.decode(Int.self) { self = .integer(val) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .null }
    }
}

class SchemaNode {
    var count: Int = 0
    var possibleTypes: Set<String> = []
    var properties: [String: SchemaNode] = [:]
    
    func merge(with value: JSONValue) {
        count += 1
        switch value {
        case .string:
            possibleTypes.insert("String")
        case .integer:
            if !possibleTypes.contains("Double") {
                possibleTypes.insert("Int")
            }
        case .double:
            possibleTypes.remove("Int")
            possibleTypes.insert("Double")
        case .bool:
            possibleTypes.insert("Bool")
        case .null:
            count -= 1
        case .array(let elements):
            possibleTypes.insert("Array")
            let child = properties["element"] ?? SchemaNode()
            for val in elements {
                child.merge(with: val)
            }
            properties["element"] = child
        case .object(let dict):
            possibleTypes.insert("Object")
            for (key, val) in dict {
                let child = properties[key] ?? SchemaNode()
                child.merge(with: val)
                properties[key] = child
            }
        }
    }
}


func analyzeJSONL(at url: URL) async throws -> SchemaNode {
    let root = SchemaNode()

    for try await line in url.lines {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        
        if let data = line.data(using: .utf8),
           let jsonObject = try? decoder.decode(JSONValue.self, from: data) {
            root.merge(with: jsonObject)
        }
    }
    return root
}

func generateSwiftStruct(name: String, node: SchemaNode, level: Int = 0) -> String {
    let space = String(repeating: "    ", count: level)

    var lines: [String] = []
    var nestedTypesIndex = 0
    var isIdentifiable = false
    
    func process(key: String, child: SchemaNode) -> (String, Bool) {
        let isOptional = child.count < node.count
        var typeName = child.possibleTypes.count > 1 ? "AnyCodable" : (child.possibleTypes.first ?? "String")
        if child.possibleTypes.contains("Object") {
            typeName = key.capitalizingFirstLetter()
            if !typeName.hasSuffix("Info") {
                typeName = typeName + "Info"
            }
            let nestedType = generateSwiftStruct(name: typeName, node: child, level: level + 1)
            lines.insert(nestedType, at: nestedTypesIndex)
            nestedTypesIndex += 1
        }
        else if child.possibleTypes.contains("Array") {
            let element = child.properties["element"]!
            typeName = "[" + process(key: key, child: element).0 + "]"
        }
        return (typeName, isOptional)
    }
    
    for (key, child) in node.properties.sorted(by: { $0.key < $1.key }) {
        let (typeName, isOptional) = process(key: key, child: child)
        
        var validKey = key
        if key == "func" {
            validKey = "`func`"
        }
        else if key == "default" {
            validKey = "`default`"
        }
        var defaultValue: String?
        if isOptional {
            defaultValue = "nil"
        }
        else if typeName == "Bool" {
            defaultValue = "false"
        }
        else if typeName == "String" {
            defaultValue = "\"\""
        }
        else if typeName == "Int" || typeName == "Double" {
            defaultValue = "0"
        }
        else if typeName.hasPrefix("[") {
            defaultValue = "[]"
        }
        
        var propertyLine = "\(space)    var \(validKey): \(typeName)\(isOptional ? "?" : "")"
        if let v = defaultValue {
            propertyLine = propertyLine + " = \(v)"
        }
        lines.append(propertyLine)
        
        if validKey == "_key" && !isOptional {
            let id = "\(space)    var id: \(typeName) { _key }"
            lines.append(id)
            isIdentifiable = true
        }

    }
    
    lines.append(space + "}\n")
    
    let declaration = isIdentifiable ?
    "\(space)struct \(name): Identifiable, Codable {\n" :
    "\(space)struct \(name): Codable {\n"
    
    return declaration + lines.joined(separator: "\n")
}

func structName(from baseName: String) -> String {
    var name = baseName.capitalizingFirstLetter()
    
    if name.hasSuffix("ies") {
        name = name.dropLast(3) + "y"
    } else if name.hasSuffix("s") && !name.hasSuffix("ss") && !name.hasSuffix("Bonus"){
        name = String(name.dropLast())
    }
    if !name.hasSuffix("Info") {
        name = name + "Info"
    }
    return name
}

let version = try decoder.decode(Version.self, from: Data(contentsOf: inputDir.appending(path: "_sde.jsonl")))

var output = """
//
// \(outputFile.lastPathComponent)
// DogmaKit
// SDE Version: \(version.buildNumber), \(version.releaseDate)
//

import Foundation

"""

for fileName in filesToProcess {
    do {
        let url = inputDir.appending(path: fileName)
        let typeName = structName(from: url.deletingPathExtension().lastPathComponent)
        let node = try await analyzeJSONL(at: url)
        let s = generateSwiftStruct(name: typeName, node: node)
        output = output + "\n" + s
    }
    catch {
        print(error)
        throw error
    }
}

try? FileManager.default.removeItem(at: outputFile)

try? FileManager.default.createDirectory(at: outputFile.deletingLastPathComponent(), withIntermediateDirectories: true)
try output.write(to: outputFile, atomically: true, encoding: .utf8)
