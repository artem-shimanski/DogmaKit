//
//  DogmaPlanetaryData.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import FlatBin
import DogmaModels

/// Flat schema of the planetary industry data (`planetary.bin`), separate from `sde.bin` and the name catalog.
/// Everything here is built by the importer from the SDE (`DogmaDataImporter/PlanetaryImport.swift`); there are no
/// handwritten tables.
@FlatCodable
public struct DogmaPlanetaryData: Sendable {

    /// A commodity quantity; used for schematic inputs and outputs.
    @FlatRawCodable
    public struct Amount: BitwiseCopyable, Hashable, Sendable {
        public var typeID: TypeID
        public var quantity: UInt32

        public init(typeID: TypeID, quantity: UInt32) {
            self.typeID = typeID
            self.quantity = quantity
        }
    }

    /// Exactly one output (true for all 68 SDE schematics; the importer checks it) and one to three inputs.
    @FlatCodable
    public struct Schematic: Identifiable, Sendable {
        public var id: SchematicID
        /// Seconds: 1800 for P1, 3600 otherwise.
        public var cycleTime: UInt32
        public var output: Amount
        /// SORTED by typeID by the importer, so the "enough materials" check is a merge of two sorted lists.
        public var inputs: [Amount]
        /// Type IDs of the processors able to run this schematic (`pins` in the SDE). Sorted.
        public var processors: [TypeID]

        public init(id: SchematicID, cycleTime: UInt32, output: Amount, inputs: [Amount], processors: [TypeID]) {
            self.id = id
            self.cycleTime = cycleTime
            self.output = output
            self.inputs = inputs
            self.processors = processors
        }
    }

    /// Commodity tier: `p0` is raw resources (Planetary Resources category), `p1...p4` are Planetary Commodities
    /// groups. Also the factory priority in the simulation.
    @FlatRawCodable
    public enum Tier: UInt8, BitwiseCopyable, Comparable, Sendable {
        case p0, p1, p2, p3, p4

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @FlatRawCodable
    public struct Commodity: BitwiseCopyable, Sendable {
        public var tier: Tier
        /// m3 per unit. `Double`, not `Float` as in `DogmaSDE`: the volume divides storage capacity
        /// (`floor(12000 / 0.19)`), where `Float` error could add or drop a unit.
        public var volume: Double

        public init(tier: Tier, volume: Double) {
            self.tier = tier
            self.volume = volume
        }
    }

    @FlatRawCodable
    public enum PinKind: UInt8, BitwiseCopyable, Sendable {
        case commandCenter
        case processor
        case storage
        case launchpad
        case extractor
    }

    /// A published pin type (groups 1027-1030, 1063). Legacy extractors (group 1026) are excluded: ESI never returns them.
    @FlatRawCodable
    public struct Pin: BitwiseCopyable, Sendable {
        public var kind: PinKind
        /// Type ID of the planet the pin is placed on (`planetRestriction`, 1632).
        public var planetTypeID: TypeID
        /// m3; 0 for processors and ECUs (a processor's buffer equals the schematic's need).
        public var capacity: Double
        public var cpuLoad: Double
        public var powerLoad: Double
        /// Command center only; these are level 0 values (see `DogmaPlanetaryData.commandCenterLevels`).
        public var cpuOutput: Double
        public var powerOutput: Double
        /// ECU only: load per head (1690 / 1691).
        public var extractorHeadCPU: Double
        public var extractorHeadPower: Double

        public init(kind: PinKind, planetTypeID: TypeID, capacity: Double,
                    cpuLoad: Double, powerLoad: Double,
                    cpuOutput: Double, powerOutput: Double,
                    extractorHeadCPU: Double, extractorHeadPower: Double) {
            self.kind = kind
            self.planetTypeID = planetTypeID
            self.capacity = capacity
            self.cpuLoad = cpuLoad
            self.powerLoad = powerLoad
            self.cpuOutput = cpuOutput
            self.powerOutput = powerOutput
            self.extractorHeadCPU = extractorHeadCPU
            self.extractorHeadPower = extractorHeadPower
        }
    }

    /// Command center resources at one upgrade level.
    @FlatRawCodable
    public struct Resources: BitwiseCopyable, Equatable, Sendable {
        public var cpu: Double
        public var power: Double

        public init(cpu: Double, power: Double) {
            self.cpu = cpu
            self.power = power
        }
    }

    /// The `Link` type (2280), the only one in the Planetary Links group.
    @FlatRawCodable
    public struct Link: BitwiseCopyable, Sendable {
        public var cpuLoad: Double
        public var powerLoad: Double
        public var cpuLoadPerKm: Double
        public var powerLoadPerKm: Double
        public var cpuLoadLevelModifier: Double
        public var powerLoadLevelModifier: Double
        /// m3/h at level 0 (`logisticalCapacity`, 1631).
        public var logisticalCapacity: Double

        public init(cpuLoad: Double = 0, powerLoad: Double = 0,
                    cpuLoadPerKm: Double = 0, powerLoadPerKm: Double = 0,
                    cpuLoadLevelModifier: Double = 0, powerLoadLevelModifier: Double = 0,
                    logisticalCapacity: Double = 0) {
            self.cpuLoad = cpuLoad
            self.powerLoad = powerLoad
            self.cpuLoadPerKm = cpuLoadPerKm
            self.powerLoadPerKm = powerLoadPerKm
            self.cpuLoadLevelModifier = cpuLoadLevelModifier
            self.powerLoadLevelModifier = powerLoadLevelModifier
            self.logisticalCapacity = logisticalCapacity
        }
    }

    /// Extractor formula constants. In the SDE these are the `defaultValue` of the attributes `ecuDecayFactor` (1683)
    /// and `ecuNoiseFactor` (1687); no type assigns them. Stored rather than hardcoded since CCP may change them.
    @FlatRawCodable
    public struct ExtractorConstants: BitwiseCopyable, Sendable {
        public var decayFactor: Double
        public var noiseFactor: Double

        public init(decayFactor: Double = 0, noiseFactor: Double = 0) {
            self.decayFactor = decayFactor
            self.noiseFactor = noiseFactor
        }
    }

    public var schematics: PerfectDictionary<SchematicID, Schematic> = [:]
    public var pins: PerfectDictionary<TypeID, Pin> = [:]
    /// P0-P4: every commodity that appears in schematics.
    public var commodities: PerfectDictionary<TypeID, Commodity> = [:]
    /// Indexed by upgrade level (ESI `upgrade_level`, 0...5). Built from the unpublished legacy command center
    /// types (Limited...Elite), whose `metaLevel` equals the level; level 0 comes from the published ones.
    public var commandCenterLevels: [Resources] = []
    // The type is explicit: `@FlatCodable` does not infer it from the initializer and silently skips unannotated properties.
    public var link: Link = Link()
    public var extractor: ExtractorConstants = ExtractorConstants()

    public init() {}
}
