//
//  Colony+Snapshot.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

extension Colony {

    /// Rebuilds a colony from a snapshot.
    ///
    /// Anything self-contradictory or inconsistent with the catalog (duplicate `pinID`, a route to a nonexistent pin,
    /// an unknown pin type, schematic or route cargo) throws `ColonyError`: such a colony cannot be simulated
    /// meaningfully. Anything simulable but not as in the game goes to `warnings`.
    ///
    /// Pin state at `T0 = snapshot.snapshotTime`:
    /// - a **processor** is running if `lastCycleStart + cycleTime > T0`; its output then appears at
    ///   `runningCycleEnd`, and `contents` is already the buffer of the NEXT cycle (the running cycle's inputs were
    ///   consumed at its start);
    /// - an **ECU** follows the cycle grid from `installTime` (as in CCP's formula); the current cycle is the one
    ///   running at `T0`, and a cycle that ended exactly at `T0` has already been delivered. `lastCycleStart` is only
    ///   checked against the grid.
    public init(snapshot: ColonySnapshot, catalog: PlanetaryCatalog) throws(ColonyError) {
        let t0 = snapshot.snapshotTime
        guard snapshot.pins.count <= Int(UInt16.max) else {
            throw .tooManyPins(count: snapshot.pins.count)
        }

        var warnings: [Warning] = []
        var indexByPinID: [Int64: PinIndex] = [:]
        var pins: [Pin] = []
        pins.reserveCapacity(snapshot.pins.count)

        for source in snapshot.pins {
            guard indexByPinID[source.pinID] == nil else { throw .duplicatePin(pinID: source.pinID) }
            guard let info = catalog.pin(source.typeID) else {
                throw .unknownPinType(pinID: source.pinID, typeID: Int64(source.typeID.rawValue))
            }
            if let planet = snapshot.planetTypeID, planet != info.planetTypeID {
                warnings.append(.planetMismatch(pinID: source.pinID))
            }

            var contents = Inventory()
            for item in source.contents where item.quantity > 0 {
                guard catalog.commodity(item.typeID) != nil else {
                    warnings.append(.unknownCommodity(pinID: source.pinID, typeID: item.typeID))
                    continue
                }
                contents[item.typeID] += item.quantity
            }

            let role: Role
            switch info.kind {
            case .commandCenter, .storage, .launchpad:
                role = .storage
            case .processor:
                role = .processor(try Self.restoreProcessor(source, at: t0, catalog: catalog, warnings: &warnings))
            case .extractor:
                role = .extractor(Self.restoreExtractor(source, at: t0, catalog: catalog, warnings: &warnings))
            }

            let index = PinIndex(rawValue: UInt16(pins.count))
            indexByPinID[source.pinID] = index
            pins.append(Pin(id: index, pinID: source.pinID, typeID: source.typeID, kind: info.kind,
                            latitude: source.latitude, longitude: source.longitude,
                            capacity: info.capacity, contents: contents, role: role))
        }

        func resolve(_ pinID: Int64) throws(ColonyError) -> PinIndex {
            guard let index = indexByPinID[pinID] else { throw .unknownPin(pinID: pinID) }
            return index
        }

        var routes: [Route] = []
        routes.reserveCapacity(snapshot.routes.count)
        for route in snapshot.routes {
            let source = try resolve(route.sourcePinID)
            let destination = try resolve(route.destinationPinID)
            guard catalog.commodity(route.typeID) != nil else {
                throw .unknownRouteCommodity(routeID: route.routeID, typeID: Int64(route.typeID.rawValue))
            }
            var waypoints: [PinIndex] = []
            for waypoint in route.waypoints {
                waypoints.append(try resolve(waypoint))
            }
            routes.append(Route(routeID: route.routeID, source: source, destination: destination,
                                typeID: route.typeID, quantity: route.quantity, waypoints: waypoints))
        }

        var links: [Link] = []
        links.reserveCapacity(snapshot.links.count)
        for link in snapshot.links {
            links.append(Link(source: try resolve(link.sourcePinID),
                              destination: try resolve(link.destinationPinID),
                              level: link.level))
        }

        self.init(catalog: catalog, snapshotTime: t0, planetTypeID: snapshot.planetTypeID,
                  upgradeLevel: snapshot.upgradeLevel, planetRadius: snapshot.planetRadius,
                  pins: pins, routes: routes, links: links, warnings: warnings)
    }

    private static func restoreProcessor(_ pin: ColonySnapshot.Pin, at t0: Date, catalog: PlanetaryCatalog,
                                         warnings: inout [Warning]) throws(ColonyError) -> Processor {
        guard let schematicID = pin.schematicID else {
            warnings.append(.processorWithoutSchematic(pinID: pin.pinID))
            return Processor(schematicID: nil, lastCycleStart: pin.lastCycleStart, runningCycleEnd: nil)
        }
        guard let schematic = catalog.schematic(schematicID) else {
            throw .unknownSchematic(pinID: pin.pinID, schematicID: Int(schematicID.rawValue))
        }
        if !schematic.processors.contains(pin.typeID) {
            warnings.append(.schematicNotSupported(pinID: pin.pinID, schematicID: schematicID))
        }
        var runningCycleEnd: Date?
        if let start = pin.lastCycleStart {
            let end = start.addingTimeInterval(TimeInterval(schematic.cycleTime))
            if end > t0 { runningCycleEnd = end }
        }
        return Processor(schematicID: schematicID, lastCycleStart: pin.lastCycleStart, runningCycleEnd: runningCycleEnd)
    }

    private static func restoreExtractor(_ pin: ColonySnapshot.Pin, at t0: Date, catalog: PlanetaryCatalog,
                                         warnings: inout [Warning]) -> Extractor {
        let details = pin.extractor
        let product = details?.productTypeID
        guard let install = pin.installTime, let expiry = pin.expiryTime,
              let cycleTime = details?.cycleTime, cycleTime > 0,
              let quantity = details?.quantityPerCycle, quantity > 0,
              let product, catalog.commodity(product) != nil else {
            if let product, catalog.commodity(product) == nil {
                warnings.append(.unknownCommodity(pinID: pin.pinID, typeID: product))
            }
            warnings.append(.extractorNotConfigured(pinID: pin.pinID))
            return Extractor(program: nil, productTypeID: product, headCount: details?.headCount ?? 0,
                             lastCycleStart: pin.lastCycleStart, pendingCycle: nil)
        }

        let program = ExtractorProgram(installTime: install, expiryTime: expiry, cycleTime: cycleTime,
                                       quantityPerCycle: quantity, constants: catalog.extractor)

        if let last = pin.lastCycleStart, program.cycle(at: last) != nil {
            let offset = Int(last.timeIntervalSince(install).rounded())
            if offset % cycleTime != 0 {
                warnings.append(.extractorCycleMisaligned(pinID: pin.pinID))
            }
        }

        let pending: Int?
        if program.cycleCount == 0 {
            pending = nil
        } else if t0 < install {
            pending = 0
        } else {
            pending = program.cycle(at: t0)
        }
        return Extractor(program: program, productTypeID: product, headCount: details?.headCount ?? 0,
                         lastCycleStart: pin.lastCycleStart, pendingCycle: pending)
    }
}

// MARK: - Reverse path: colony to snapshot

extension Colony {

    /// A snapshot from which `Colony.init(snapshot:catalog:)` rebuilds this same colony.
    ///
    /// It is both the planner's document (edits are made on `ColonySnapshot`, a plain value, and the colony is
    /// rebuilt, so all validation stays in one place) and a way to persist simulation state:
    /// `simulation.snapshot` describes the colony at `simulation.time`.
    ///
    /// `time` is the moment the contents and cycles correspond to; it defaults to the original snapshot moment.
    /// For an ECU `lastCycleStart` is the start of the current cycle (derived from `pendingCycle`); for a processor,
    /// the start of the running cycle.
    public func snapshot(at time: Date? = nil) -> ColonySnapshot {
        let pins = self.pins.map { pin -> ColonySnapshot.Pin in
            var result = ColonySnapshot.Pin(pinID: pin.pinID, typeID: pin.typeID,
                                            latitude: pin.latitude, longitude: pin.longitude,
                                            contents: pin.contents.items)
            switch pin.role {
            case .storage:
                break
            case .processor(let processor):
                result.schematicID = processor.schematicID
                result.lastCycleStart = processor.lastCycleStart
            case .extractor(let extractor):
                result.installTime = extractor.program?.installTime
                result.expiryTime = extractor.program?.expiryTime
                result.lastCycleStart = extractor.pendingCycle.flatMap { extractor.program?.cycleStart($0) }
                    ?? extractor.lastCycleStart
                result.extractor = .init(productTypeID: extractor.productTypeID,
                                         cycleTime: extractor.program?.cycleTime,
                                         quantityPerCycle: extractor.program?.quantityPerCycle,
                                         headCount: extractor.headCount)
            }
            return result
        }
        let routes = self.routes.map { route in
            ColonySnapshot.Route(routeID: route.routeID,
                                 sourcePinID: self[route.source].pinID,
                                 destinationPinID: self[route.destination].pinID,
                                 typeID: route.typeID, quantity: route.quantity,
                                 waypoints: route.waypoints.map { self[$0].pinID })
        }
        let links = self.links.map { link in
            ColonySnapshot.Link(sourcePinID: self[link.source].pinID,
                                destinationPinID: self[link.destination].pinID,
                                level: link.level)
        }
        return ColonySnapshot(snapshotTime: time ?? snapshotTime, planetTypeID: planetTypeID,
                              upgradeLevel: upgradeLevel, planetRadius: planetRadius,
                              pins: pins, routes: routes, links: links)
    }
}

extension ColonySimulation {
    /// The colony's state at the current simulation moment as a snapshot.
    public var snapshot: ColonySnapshot {
        colony.snapshot(at: time)
    }
}
