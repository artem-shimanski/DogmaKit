//
//  TextCatalog.swift
//  DogmaText
//
//  Created by Artem Shimanski on 02.08.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
import DogmaTextResources
#endif
import FlatBin
import DogmaModels

/// Read-only name catalog over `text-en.bin`. The file is memory-mapped and each query is a direct
/// minimal-perfect-hash lookup; only the requested string is materialized. Independent of the engine.
public struct TextCatalog: Sendable {
    let decoder: FlatDecoder

    /// Lazy name-to-ID index for `TypeResolver`; empty until the first resolve.
    let index = ReverseIndex()

    /// A catalog from an arbitrary file (custom build, server download, app cache).
    public init(contentsOf url: URL) throws {
        decoder = FlatDecoder(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    public init(data: Data) {
        decoder = FlatDecoder(data: data)
    }

    /// English catalog from the `DogmaTextResources` bundle, or on WebAssembly from `text-en.bin` next to the
    /// executable.
    public static func english() throws -> TextCatalog {
        #if os(WASI)
        let url: URL? = executableDirectory.appending(path: "text-en.bin")
        #else
        let url = DogmaTextResources.english
        #endif
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try TextCatalog(contentsOf: url)
    }

    // A local copy of `decoder` in each method: the view is a borrow, and taking it from the stored property triggers lifetime diagnostics.

    public func name(of id: TypeID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).types[id]?.load()
    }

    public func name(of id: GroupID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).groups[id]?.load()
    }

    public func name(of id: CategoryID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).categories[id]?.load()
    }

    public func name(of id: MetaGroupID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).metaGroups[id]?.load()
    }

    /// Internal, non-localized attribute name (`cpu`, `speedFactor`).
    public func name(of id: AttributeID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).attributes[id]?.load()
    }

    public func name(of id: AttributeCategoryID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).attributeCategories[id]?.load()
    }

    /// Internal effect name (`shipModuleRemoteArmorMutadaptiveRepairer`).
    public func name(of id: EffectID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).effects[id]?.load()
    }

    public func name(of id: WarfareBuffID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).warfareBuffs[id]?.load()
    }

    /// Internal unit name (`Length`, `Mass`).
    public func name(of id: UnitID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).units[id]?.load()
    }

    /// PI schematic name (`Superconductors`).
    public func name(of id: SchematicID) -> String? {
        let decoder = decoder
        return decoder.decode(DogmaTextData.self).schematics[id]?.load()
    }
}
