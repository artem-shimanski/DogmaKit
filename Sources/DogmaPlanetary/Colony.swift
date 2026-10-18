//
//  Colony.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// A colony on one planet at the snapshot moment: the uniform state the simulation starts from.
///
/// A value, not an actor: there is no shared mutable state, a colony is a few dozen pins and cheap to copy, and the
/// simulation is pure and synchronous.
///
/// The snapshot is resolved once, so every pin already records what it is doing at `snapshotTime` and when it finishes.
public struct Colony: Sendable {

    /// Dense index of a pin in `pins`. ESI `pin_id` is an `Int64` and unsuitable for indexing; the index is also the
    /// tie-break for ordering in the simulation, which makes runs deterministic.
    public struct PinIndex: RawRepresentable, Hashable, Comparable, Sendable, CustomStringConvertible {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        public var description: String { "#\(rawValue)" }
    }

    public struct Pin: Identifiable, Sendable {
        public let id: PinIndex
        /// ESI `pin_id`.
        public let pinID: Int64
        public let typeID: TypeID
        public let kind: DogmaPlanetaryData.PinKind
        public let latitude: Double
        public let longitude: Double
        /// Capacity, m3; 0 for processors and ECUs.
        public let capacity: Double
        /// Contents at snapshot time. For a processor, the input buffer of the NEXT cycle (the running cycle's inputs were consumed at its start).
        public var contents: Inventory
        public var role: Role
    }

    public enum Role: Hashable, Sendable {
        /// Command center, storage, launchpad: they only store.
        case storage
        case processor(Processor)
        case extractor(Extractor)
    }

    public struct Processor: Hashable, Sendable {
        /// `nil` means no schematic chosen: the processor stands idle.
        public var schematicID: SchematicID?
        public var lastCycleStart: Date?
        /// End of the cycle running at snapshot time; `nil` if the processor was idle. That cycle's output is not yet produced; it appears at this moment.
        public var runningCycleEnd: Date?

        public init(schematicID: SchematicID?, lastCycleStart: Date?, runningCycleEnd: Date?) {
            self.schematicID = schematicID
            self.lastCycleStart = lastCycleStart
            self.runningCycleEnd = runningCycleEnd
        }
    }

    public struct Extractor: Hashable, Sendable {
        /// `nil` if the program is not set or incomplete (no `qty_per_cycle`, install/expiry time or cycle duration): such an ECU is not modeled.
        public var program: ExtractorProgram?
        public var productTypeID: TypeID?
        public var headCount: Int
        public var lastCycleStart: Date?
        /// The cycle running at snapshot time (or the first, if the program has not started): its output arrives at
        /// `program.cycleEnd(pendingCycle)`. `nil` if the program is finished or not set.
        public var pendingCycle: Int?

        public init(program: ExtractorProgram?, productTypeID: TypeID?, headCount: Int,
                    lastCycleStart: Date?, pendingCycle: Int?) {
            self.program = program
            self.productTypeID = productTypeID
            self.headCount = headCount
            self.lastCycleStart = lastCycleStart
            self.pendingCycle = pendingCycle
        }
    }

    public struct Route: Hashable, Sendable {
        public let routeID: Int64
        public let source: PinIndex
        public let destination: PinIndex
        public let typeID: TypeID
        /// As received from ESI. NOT used as a limit in the simulation: the semantics are unconfirmed.
        public let quantity: Double
        public let waypoints: [PinIndex]
    }

    public struct Link: Hashable, Sendable {
        public let source: PinIndex
        public let destination: PinIndex
        public let level: Int
    }

    /// Non-fatal snapshot quirks: the colony is built, but something is modeled differently from the game or not at
    /// all. Numbers are raw `rawValue`/`pin_id`, not ID `description`, which prints a name when a debug catalog is installed.
    public enum Warning: Hashable, Sendable, CustomStringConvertible {
        /// An ECU without a complete program extracts nothing.
        case extractorNotConfigured(pinID: Int64)
        /// The ECU's `last_cycle_start` is off the cycle grid from `install_time`. The grid is taken from installation (as in CCP's formula).
        case extractorCycleMisaligned(pinID: Int64)
        /// A processor without a schematic stands idle.
        case processorWithoutSchematic(pinID: Int64)
        /// The schematic is not one this processor type can run.
        case schematicNotSupported(pinID: Int64, schematicID: SchematicID)
        /// `contents` holds a commodity absent from the catalog; the entry was dropped.
        case unknownCommodity(pinID: Int64, typeID: TypeID)
        /// The pin type is meant for another planet.
        case planetMismatch(pinID: Int64)

        public var description: String {
            switch self {
            case .extractorNotConfigured(let pin): "extractor \(pin): program is not configured"
            case .extractorCycleMisaligned(let pin): "extractor \(pin): last cycle start is off the cycle grid"
            case .processorWithoutSchematic(let pin): "processor \(pin): no schematic"
            case .schematicNotSupported(let pin, let schematic): "processor \(pin): schematic \(schematic.rawValue) is not supported by this type"
            case .unknownCommodity(let pin, let type): "pin \(pin): unknown commodity \(type.rawValue) dropped"
            case .planetMismatch(let pin): "pin \(pin): built for another planet type"
            }
        }
    }

    /// The catalog the colony was built against; the simulation needs the same one.
    public let catalog: PlanetaryCatalog
    /// Snapshot moment (`last_update` from the colony list).
    public let snapshotTime: Date
    /// Planet type ID; `nil` if unknown.
    public let planetTypeID: TypeID?
    /// 0...5.
    public let upgradeLevel: Int
    /// Meters; `nil` if link lengths are unknown.
    public let planetRadius: Double?
    // `internal(set)`: the simulation writes state back into its own copy of the colony.
    public internal(set) var pins: [Pin]
    /// Sorted by `(source, routeID)`: routes of one source form a segment ordered by `route_id` (`routes(from:)`).
    public let routes: [Route]
    public let links: [Link]
    public let warnings: [Warning]

    private let indexByPinID: [Int64: PinIndex]
    /// Start of each pin's route segment in `routes`; `routeStarts[i + 1]` is its end.
    private let routeStarts: [Int]
    /// Incoming routes of each pin: indices into `routes`, by `(source, routeID)`.
    private let incoming: [[Int]]

    init(catalog: PlanetaryCatalog, snapshotTime: Date, planetTypeID: TypeID?, upgradeLevel: Int, planetRadius: Double?,
         pins: [Pin], routes: [Route], links: [Link], warnings: [Warning]) {
        self.catalog = catalog
        self.snapshotTime = snapshotTime
        self.planetTypeID = planetTypeID
        self.upgradeLevel = upgradeLevel
        self.planetRadius = planetRadius
        self.pins = pins
        let routes = routes.sorted { ($0.source, $0.routeID) < ($1.source, $1.routeID) }
        self.routes = routes
        self.links = links
        self.warnings = warnings
        self.indexByPinID = Dictionary(uniqueKeysWithValues: pins.map { ($0.pinID, $0.id) })

        var starts = [Int](repeating: 0, count: pins.count + 1)
        var incoming = [[Int]](repeating: [], count: pins.count)
        for (offset, route) in routes.enumerated() {
            starts[Int(route.source.rawValue) + 1] += 1
            incoming[Int(route.destination.rawValue)].append(offset)
        }
        for i in 0..<pins.count { starts[i + 1] += starts[i] }
        self.routeStarts = starts
        self.incoming = incoming
    }

    // MARK: - Access

    public subscript(_ index: PinIndex) -> Pin {
        pins[Int(index.rawValue)]
    }

    /// Pin by ESI `pin_id`.
    public subscript(pinID pinID: Int64) -> Pin? {
        index(ofPinID: pinID).map { self[$0] }
    }

    public func index(ofPinID pinID: Int64) -> PinIndex? {
        indexByPinID[pinID]
    }

    /// Outgoing routes of a pin, by `route_id`.
    public func routes(from source: PinIndex) -> ArraySlice<Route> {
        let i = Int(source.rawValue)
        return routes[routeStarts[i]..<routeStarts[i + 1]]
    }

    /// Incoming routes of a pin, by `(source, route_id)`.
    public func routes(to destination: PinIndex) -> [Route] {
        incoming[Int(destination.rawValue)].map { routes[$0] }
    }

    /// The processor's schematic, if chosen and known to the catalog.
    public func schematic(of index: PinIndex) -> DogmaPlanetaryData.Schematic? {
        guard case .processor(let processor) = self[index].role, let id = processor.schematicID else { return nil }
        return catalog.schematic(id)
    }
}

/// The colony cannot be built: the snapshot contradicts itself or the catalog.
public enum ColonyError: Error, Hashable, Sendable {
    case duplicatePin(pinID: Int64)
    /// The pin type is not among the catalog's published pins.
    case unknownPinType(pinID: Int64, typeID: Int64)
    /// A route or link references a pin that is not in the layout.
    case unknownPin(pinID: Int64)
    case unknownSchematic(pinID: Int64, schematicID: Int)
    /// A route carries something that is not in the commodity catalog.
    case unknownRouteCommodity(routeID: Int64, typeID: Int64)
    /// More pins than fit into `PinIndex`.
    case tooManyPins(count: Int)
}
