//
//  FitDocument.swift
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

/// Native fit exchange format.
///
/// The document mirrors the write API rather than dumping the model: import replays it
/// through `Fit`, so all validation is reused.
///
/// - Derived data is not stored (module slot, hardpoint, drone squadron, implant slot,
///   resulting type of a mutated item).
/// - Defaults are omitted: `nil` means "use the default", not zero.
/// - References are positional: `target` is a pilot index in `pilots`, not an `EntityID`.
public struct FitDocument: Codable, Equatable, Sendable {
    public static let formatIdentifier = "dogmakit.fit"
    public static let currentVersion = 1

    /// Always `"dogmakit.fit"`; distinguishes the document from arbitrary JSON.
    public var format: String
    /// Schema version. Bumped only on incompatible changes.
    public var version: Int
    /// Fit name.
    public var name: String?
    /// SDE version label at export time. Diagnostic only.
    public var sde: String?
    /// Simulation environment: beacon effects, weather, storms.
    public var environment: [Item]
    /// Order matters: the index is the address used by `target`.
    public var pilots: [Pilot]

    public init(name: String? = nil,
                sde: String? = nil,
                environment: [Item] = [],
                pilots: [Pilot] = []) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.name = name
        self.sde = sde
        self.environment = environment
        self.pilots = pilots
    }

    enum CodingKeys: String, CodingKey {
        case format, version, name, sde, environment, pilots
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? Self.formatIdentifier
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        name = try c.decodeIfPresent(String.self, forKey: .name)
        sde = try c.decodeIfPresent(String.self, forKey: .sde)
        environment = try c.decodeIfPresent([Item].self, forKey: .environment) ?? []
        pilots = try c.decodeIfPresent([Pilot].self, forKey: .pilots) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(sde, forKey: .sde)
        if !environment.isEmpty { try c.encode(environment, forKey: .environment) }
        try c.encode(pilots, forKey: .pilots)
    }
}

// MARK: - Item

extension FitDocument {
    /// A type reference. Encoded as a bare number (`13219`), or as an object with a name
    /// (`{"type": 13219, "_name": "…"}`). The name is informational and never read on import.
    public struct Item: Codable, Equatable, Sendable, ExpressibleByIntegerLiteral {
        public var type: TypeID
        public var name: String?

        public init(_ type: TypeID, name: String? = nil) {
            self.type = type
            self.name = name
        }

        public init(integerLiteral value: UInt32) {
            self.init(TypeID(rawValue: value))
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name = "_name"
        }

        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let type = try? single.decode(TypeID.self) {
                self.type = type
                self.name = nil
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try c.decode(TypeID.self, forKey: .type)
            self.name = try c.decodeIfPresent(String.self, forKey: .name)
        }

        public func encode(to encoder: Encoder) throws {
            guard let name else {
                var single = encoder.singleValueContainer()
                try single.encode(type)
                return
            }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encode(name, forKey: .name)
        }
    }
}

// MARK: - Pilot

extension FitDocument {
    public struct Pilot: Codable, Equatable, Sendable {
        /// Pilot label within the fleet.
        public var name: String?
        public var skills: Skills?
        /// The slot is derived from `implantness`, so only the type is stored.
        public var implants: [Item]
        /// The slot is derived from `boosterness`.
        public var boosters: [Item]
        /// Absent means the pilot is in a capsule.
        public var ship: Ship?

        public init(name: String? = nil,
                    skills: Skills? = nil,
                    implants: [Item] = [],
                    boosters: [Item] = [],
                    ship: Ship? = nil) {
            self.name = name
            self.skills = skills
            self.implants = implants
            self.boosters = boosters
            self.ship = ship
        }

        enum CodingKeys: String, CodingKey {
            case name, skills, implants, boosters, ship
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            skills = try c.decodeIfPresent(Skills.self, forKey: .skills)
            implants = try c.decodeIfPresent([Item].self, forKey: .implants) ?? []
            boosters = try c.decodeIfPresent([Item].self, forKey: .boosters) ?? []
            ship = try c.decodeIfPresent(Ship.self, forKey: .ship)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(name, forKey: .name)
            try c.encodeIfPresent(skills, forKey: .skills)
            if !implants.isEmpty { try c.encode(implants, forKey: .implants) }
            if !boosters.isEmpty { try c.encode(boosters, forKey: .boosters) }
            try c.encodeIfPresent(ship, forKey: .ship)
        }
    }
}

// MARK: - Skills

extension FitDocument {
    /// Default level plus exceptions.
    ///
    /// The full skill list is not written: it would freeze today's SDE skill set into the
    /// document, and a new skill would import at 0 in an "all V" fit. Maps onto
    /// `Fit.Pilots.add(skillLevel:)` + `Fit.Skills.setLevels(_:)`.
    public struct Skills: Codable, Equatable, Sendable {
        public var `default`: UInt8
        /// Only skills whose level differs from `default`, sorted by `type`.
        public var levels: [Level]

        public init(default level: UInt8 = 0, levels: [Level] = []) {
            self.default = level
            self.levels = levels
        }

        enum CodingKeys: String, CodingKey {
            case `default`, levels
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.default = try c.decodeIfPresent(UInt8.self, forKey: .default) ?? 0
            self.levels = try c.decodeIfPresent([Level].self, forKey: .levels) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(self.default, forKey: .default)
            if !levels.isEmpty { try c.encode(levels, forKey: .levels) }
        }

        public struct Level: Codable, Equatable, Sendable {
            public var type: TypeID
            public var level: UInt8
            /// Informational name; not read on import.
            public var name: String?

            public init(type: TypeID, level: UInt8, name: String? = nil) {
                self.type = type
                self.level = level
                self.name = name
            }

            enum CodingKeys: String, CodingKey {
                case type, level
                case name = "_name"
            }
        }
    }
}

// MARK: - Ship

extension FitDocument {
    public struct Ship: Codable, Equatable, Sendable {
        public var type: TypeID
        /// Informational name; not read on import.
        public var name: String?
        /// Sorted by (slot, socket). The slot itself is derived from the type's effects.
        public var modules: [Module]
        public var drones: [Drone]

        public init(type: TypeID,
                    name: String? = nil,
                    modules: [Module] = [],
                    drones: [Drone] = []) {
            self.type = type
            self.name = name
            self.modules = modules
            self.drones = drones
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name = "_name"
            case modules, drones
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(TypeID.self, forKey: .type)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            modules = try c.decodeIfPresent([Module].self, forKey: .modules) ?? []
            drones = try c.decodeIfPresent([Drone].self, forKey: .drones) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encodeIfPresent(name, forKey: .name)
            if !modules.isEmpty { try c.encode(modules, forKey: .modules) }
            if !drones.isEmpty { try c.encode(drones, forKey: .drones) }
        }
    }
}

// MARK: - Module

extension FitDocument {
    public struct Module: Codable, Equatable, Sendable {
        /// The base type, even for a mutated module: the resulting type is derived from the mutaplasmid.
        public var type: TypeID
        /// Informational name; not read on import.
        public var name: String?
        /// Physical slot index in the rack. Written only when there is a gap: an empty slot
        /// between modules affects heat spread (`heatAttenuation ^ |Δsocket|`) and cannot be
        /// recovered from the order. `nil` means the next free slot.
        public var socket: Int?
        /// `nil` means the type's default: `.active` for activatable modules, `.online` for
        /// the rest, `.offline` for types without an online effect (rigs, subsystems).
        public var state: State?
        public var charge: Item?
        /// Pilot index in `pilots`; the target is that pilot's hull.
        public var target: Int?
        public var mutation: Mutation?

        public init(type: TypeID,
                    name: String? = nil,
                    socket: Int? = nil,
                    state: State? = nil,
                    charge: Item? = nil,
                    target: Int? = nil,
                    mutation: Mutation? = nil) {
            self.type = type
            self.name = name
            self.socket = socket
            self.state = state
            self.charge = charge
            self.target = target
            self.mutation = mutation
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name = "_name"
            case socket, state, charge, target, mutation
        }

        public enum State: String, Codable, Equatable, Sendable {
            case offline, online, active, overloaded
        }
    }
}

// MARK: - Drone

extension FitDocument {
    public struct Drone: Codable, Equatable, Sendable {
        /// The base type (mutated drones exist).
        public var type: TypeID
        /// Informational name; not read on import.
        public var name: String?
        /// Stack / squadron size. `nil` means a full squadron.
        public var count: UInt8?
        /// Whether deployed in space. `nil` means `false`.
        public var active: Bool?
        /// Kamikaze mode.
        public var kamikaze: Bool?
        /// Pilot index in `pilots`.
        public var target: Int?
        public var mutation: Mutation?

        public init(type: TypeID,
                    name: String? = nil,
                    count: UInt8? = nil,
                    active: Bool? = nil,
                    kamikaze: Bool? = nil,
                    target: Int? = nil,
                    mutation: Mutation? = nil) {
            self.type = type
            self.name = name
            self.count = count
            self.active = active
            self.kamikaze = kamikaze
            self.target = target
            self.mutation = mutation
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name = "_name"
            case count, active, kamikaze, target, mutation
        }
    }
}

// MARK: - Mutation

extension FitDocument {
    public struct Mutation: Codable, Equatable, Sendable {
        public var mutaplasmid: Item
        /// Only rolled attributes: a roll equal to the base value is omitted (multiplier 1.0).
        public var rolls: [Roll]

        public init(mutaplasmid: Item, rolls: [Roll] = []) {
            self.mutaplasmid = mutaplasmid
            self.rolls = rolls
        }

        enum CodingKeys: String, CodingKey {
            case mutaplasmid, rolls
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mutaplasmid = try c.decode(Item.self, forKey: .mutaplasmid)
            rolls = try c.decodeIfPresent([Roll].self, forKey: .rolls) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(mutaplasmid, forKey: .mutaplasmid)
            if !rolls.isEmpty { try c.encode(rolls, forKey: .rolls) }
        }

        /// The value is absolute, as in the game and ESI; the multiplier is derived.
        public struct Roll: Codable, Equatable, Sendable {
            public var attribute: AttributeID
            public var value: Double

            public init(attribute: AttributeID, value: Double) {
                self.attribute = attribute
                self.value = value
            }
        }
    }
}
