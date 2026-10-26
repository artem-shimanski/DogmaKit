//
//  FitImporter.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import DogmaKit

/// Imports fits from public formats into the native `FitDocument`.
///
/// All formats converge on a document, not a `Fit`, so validation stays in one place (`Fit.load`) and the parsers
/// remain pure transformations testable without the engine.
///
/// ```swift
/// let importer = try FitImporter(resolver: myNames)
/// let result = importer.load(clipboard)
/// for document in result.documents {
///     try await engine.load(document)
/// }
/// ```
public struct FitImporter: Sendable {

    public enum Format: Sendable, CaseIterable {
        /// Clipboard text format, with the mutation extension.
        case eft
        /// One-line `shipID:typeID;qty:...` from chat links.
        case dna
        /// `<fittings>`: a fit export file from the game.
        case xml
    }

    public let resolver: any TypeResolver
    public let catalog: TypeCatalog
    /// Skill level of the imported pilot. Public formats carry no skills, and an all-zero pilot would give a fit that
    /// looks like nothing in the game.
    public let skillLevel: UInt8

    public init(resolver: any TypeResolver, catalog: TypeCatalog, skillLevel: UInt8 = 5) {
        self.resolver = resolver
        self.catalog = catalog
        self.skillLevel = skillLevel
    }

    public init(resolver: any TypeResolver, skillLevel: UInt8 = 5) throws {
        self.init(resolver: resolver, catalog: try TypeCatalog(), skillLevel: skillLevel)
    }

    // MARK: - Parsing

    public func load(_ text: String, as format: Format) -> ImportResult {
        switch format {
        case .eft: return EFTImporter(self).parse(text)
        case .dna: return DNAImporter(self).parse(text)
        case .xml: return XMLImporter(self).parse(text)
        }
    }

    /// Parses with automatic format detection.
    public func load(_ text: String) -> ImportResult {
        guard let format = Self.detect(text) else {
            return ImportResult(warnings: [.noFitsFound])
        }
        return load(text, as: format)
    }

    /// The format is detected from the first non-empty character and the structure of the first line; these formats have no signature.
    public static func detect(_ text: String) -> Format? {
        let trimmed = text.trimmed
        guard let first = trimmed.first else { return nil }
        // A chat link `<url=fitting:...>` starts with an angle bracket but is DNA, not XML, so check it first.
        if trimmed.contains("fitting:") { return .dna }
        if first == "<" { return .xml }
        if first == "[" { return .eft }
        // DNA: the first line is `shipID:` followed by `typeID;qty`. Neither EFT nor XML can start that way.
        let line = trimmed.prefix { !$0.isNewline }
        if line.contains(":"), let head = line.split(separator: ":").first,
           head.allSatisfy(\.isNumber), !head.isEmpty {
            return .dna
        }
        return nil
    }

    // MARK: - Shared by parsers

    /// Where a type goes in the document. Decided by the CATEGORY from `sde.bin`, not by the format's section:
    /// EFT sections are separated by empty lines, which are lost when copying through messengers.
    enum Placement {
        case module
        case implant
        case booster
        case drone
        case charge
        case cargo
    }

    func placement(of typeID: TypeID) -> Placement? {
        guard let categoryID = catalog.categoryID(of: typeID) else { return nil }
        switch categoryID {
        case .module, .subsystem, .structureModule:
            return .module
        case .drone, .fighter:
            return .drone
        case .charge:
            return .charge
        case .implant:
            // Implants and boosters share one SDE category and differ by the slot attribute, as in `Fit`.
            if catalog.attribute(.implantness, of: typeID) != nil { return .implant }
            if catalog.attribute(.boosterness, of: typeID) != nil { return .booster }
            return .cargo
        default:
            return .cargo
        }
    }

    /// An empty document with one pilot and a hull: the starting point of all parsers.
    func makeDocument(name: String?, ship typeID: TypeID) -> FitDocument {
        FitDocument(name: name,
                    pilots: [.init(skills: .init(default: skillLevel),
                                   ship: .init(type: typeID))])
    }
}
