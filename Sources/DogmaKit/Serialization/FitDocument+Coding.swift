//
//  FitDocument+Coding.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import DogmaModels

extension FitDocument {

    /// Encodes the document as JSON with sorted keys.
    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        : [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(FitDocument.self, from: jsonData)
    }
}

// MARK: - Warnings

extension FitDocument {

    /// An import issue. Collected in lenient mode, thrown in strict mode.
    public enum Warning: Error, Sendable {
        /// `format` is not `"dogmakit.fit"`; possibly foreign JSON.
        case unknownFormat(String)
        /// The document is newer than the known schema; some data may be lost.
        case unsupportedVersion(Int)
        /// The pilot could not be added (e.g. more pilots than an `EntityID` can hold, at most 7).
        case pilotRejected(index: Int, DogmaError)
        /// The type is missing from the SDE or not accepted at this place in the fit.
        case typeRejected(TypeID, DogmaError)
        /// The skill is missing from the current SDE.
        case skillNotFound(TypeID)
        /// The charge does not fit the module.
        case chargeRejected(TypeID, to: TypeID, DogmaError)
        /// The mutaplasmid could not be applied (missing from the SDE or not for this type).
        case mutationRejected(TypeID, on: TypeID, DogmaError)
        /// The roll could not be applied: the attribute is outside the mutaplasmid's ranges.
        case rollRejected(AttributeID, on: TypeID, DogmaError)
        /// `target` refers to a pilot that is not in the document.
        case targetOutOfRange(Int)
        /// A value (state, squadron size, …) was clamped.
        case valueClamped(TypeID, String)
    }
}

extension FitDocument.Warning: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unknownFormat(format):
            return "unknown document format \"\(format)\""
        case let .unsupportedVersion(version):
            return "document version \(version) is newer than \(FitDocument.currentVersion)"
        case let .pilotRejected(index, error):
            return "pilot #\(index) rejected: \(error)"
        case let .typeRejected(typeID, error):
            return "type \(typeID.rawValue) rejected: \(error)"
        case let .skillNotFound(typeID):
            return "skill \(typeID.rawValue) is missing in SDE"
        case let .chargeRejected(charge, module, error):
            return "charge \(charge.rawValue) rejected by module \(module.rawValue): \(error)"
        case let .mutationRejected(mutaplasmid, typeID, error):
            return "mutaplasmid \(mutaplasmid.rawValue) rejected on \(typeID.rawValue): \(error)"
        case let .rollRejected(attributeID, typeID, error):
            return "roll of attribute \(attributeID.rawValue) rejected on \(typeID.rawValue): \(error)"
        case let .targetOutOfRange(index):
            return "target points at pilot #\(index), which is not in the document"
        case let .valueClamped(typeID, what):
            return "\(what) clamped on type \(typeID.rawValue)"
        }
    }
}

// MARK: - Module state

extension FitDocument.Module.State {

    public init(_ state: Entity.Module.State) {
        switch state {
        case .offline: self = .offline
        case .online: self = .online
        case .active: self = .active
        case .overloaded: self = .overloaded
        }
    }

    public var state: Entity.Module.State {
        switch self {
        case .offline: return .offline
        case .online: return .online
        case .active: return .active
        case .overloaded: return .overloaded
        }
    }
}
