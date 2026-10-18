//
//  FitDocument+Export.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

import DogmaModels

extension DogmaEngine {

    /// Exports the fit as a document.
    ///
    /// Reads the entity store, not `FitStats`, so the document does not depend on calculation
    /// results. Does not trigger a recalculation.
    ///
    /// `names` optionally supplies human-readable type names (the SDE binary has none, since
    /// names are localized). They go into `_name` fields, which import ignores.
    public func export(name: String? = nil,
                       sde: String? = nil,
                       names: (@Sendable (TypeID) -> String?)? = nil) -> FitDocument {
        session.export(name: name, sde: sde, names: names, only: nil)
    }

    /// Exports a document with a single pilot of the fleet, for consumers that store each
    /// ship as a separate record. Differs from `export(name:sde:names:)`:
    /// - all `target`s are omitted, since a pilot index means nothing outside the fleet;
    /// - `environment` is not included: it is fleet-wide, and `Fit.load` appends to the
    ///   session, so loading N ship records would duplicate it N times.
    ///
    /// An unknown pilot is not an error: the result has no pilots.
    public func export(pilot: PilotID,
                       name: String? = nil,
                       sde: String? = nil,
                       names: (@Sendable (TypeID) -> String?)? = nil) -> FitDocument {
        session.export(name: name, sde: sde, names: names, only: pilot.rawValue)
    }
}

extension DogmaEngine.Session {

    func export(name: String?,
                sde sdeVersion: String?,
                names: (@Sendable (TypeID) -> String?)?,
                only single: EntityID?) -> FitDocument {
        var document = FitDocument(name: name, sde: sdeVersion)

        if let single {
            // Empty `pilots` means targets are not addressable; environment is fleet-wide.
            guard entities.ids(in: .pilot()).contains(single) else { return document }
            document.pilots.append(exportPilot(single, pilots: [], names: names))
            return document
        }

        for id in entities.ids(in: .environment()) {
            guard let entity = entities[id] else { continue }
            document.environment.append(item(entity.typeID, names))
        }

            // Pilot order defines `target` addressing.
        let pilotIDs = Array(entities.ids(in: .pilot()))
        for pilotID in pilotIDs {
            document.pilots.append(exportPilot(pilotID, pilots: pilotIDs, names: names))
        }
        return document
    }

    // MARK: - Pilot

    private func exportPilot(_ pilotID: EntityID,
                             pilots: [EntityID],
                             names: (@Sendable (TypeID) -> String?)?) -> FitDocument.Pilot {
        var pilot = FitDocument.Pilot()
        pilot.skills = exportSkills(pilotID, names: names)

        for id in entities.ids(in: .implant(for: pilotID)) {
            guard let entity = entities[id] else { continue }
            pilot.implants.append(item(entity.typeID, names))
        }
        for id in entities.ids(in: .booster(for: pilotID)) {
            guard let entity = entities[id] else { continue }
            pilot.boosters.append(item(entity.typeID, names))
        }

        let hullID = EntityID.hull(for: pilotID)
        if let hull = entities[hullID] {
            var ship = FitDocument.Ship(type: hull.typeID, name: names?(hull.typeID))
            ship.modules = exportModules(on: hullID, pilots: pilots, names: names)
            ship.drones = exportDrones(on: hullID, pilots: pilots, names: names)
            // Every pilot starts in a capsule; write it only if it holds something.
            if hull.typeID != .capsule || !ship.modules.isEmpty || !ship.drones.isEmpty {
                pilot.ship = ship
            }
        }
        return pilot
    }

    /// `default` is the mode of the level distribution, so "all V except three" collapses
    /// to a few entries.
    private func exportSkills(_ pilotID: EntityID,
                              names: (@Sendable (TypeID) -> String?)?) -> FitDocument.Skills? {
        var levels: [(typeID: TypeID, level: UInt8)] = []
        var histogram = [Int](repeating: 0, count: 6)

        for id in entities.ids(in: .skill(for: pilotID)) {
            guard let entity = entities[id], let level = entity.kind.skillLevel else { continue }
            levels.append((entity.typeID, level))
            if level < 6 { histogram[Int(level)] += 1 }
        }
        guard !levels.isEmpty else { return nil }

        var mostCommon: UInt8 = 0
        var bestCount = 0
        for level in 0..<6 where histogram[level] > bestCount {
            bestCount = histogram[level]
            mostCommon = UInt8(level)
        }

        let exceptions = levels
            .filter { $0.level != mostCommon }
            .sorted { $0.typeID.rawValue < $1.typeID.rawValue }
            .map { FitDocument.Skills.Level(type: $0.typeID, level: $0.level, name: names?($0.typeID)) }

        return FitDocument.Skills(default: mostCommon, levels: exceptions)
    }

    // MARK: - Modules

    private func exportModules(on hullID: EntityID,
                               pilots: [EntityID],
                               names: (@Sendable (TypeID) -> String?)?) -> [FitDocument.Module] {
        var result: [FitDocument.Module] = []

        for slot in Entity.Module.Slot.allCases {
            // Order racks by socket, not by insertion: sockets can be swapped and affect heat.
            let ids = entities.ids(in: .module(in: slot, on: hullID))
                .compactMap { entities[$0] }
                .sorted { ($0.kind.module?.socket ?? 0) < ($1.kind.module?.socket ?? 0) }

            var expectedSocket: UInt8 = 0
            for entity in ids {
                guard let module = entity.kind.module else { continue }
                // Mutated modules are written with their base type.
                let typeID = baseTypeID(of: entity.id) ?? entity.typeID

                var item = FitDocument.Module(type: typeID, name: names?(typeID))
                if module.socket != expectedSocket {
                    item.socket = Int(module.socket)
                }
                expectedSocket = module.socket &+ 1

                let defaultState: Entity.Module.State = min(module.flags.maxAllowedState, .active)
                if module.state != defaultState {
                    item.state = .init(module.state)
                }
                if let charge = entities[.charge(in: entity.id)] {
                    item.charge = self.item(charge.typeID, names)
                }
                if module.target != .invalid,
                   let index = pilots.firstIndex(of: module.target.pilot) {
                    item.target = index
                }
                item.mutation = exportMutation(of: entity, names: names)
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Drones

    private func exportDrones(on hullID: EntityID,
                              pilots: [EntityID],
                              names: (@Sendable (TypeID) -> String?)?) -> [FitDocument.Drone] {
        var result: [FitDocument.Drone] = []

        for squadron in Entity.Drone.Squadron.allCases {
            for id in entities.ids(in: .drone(in: squadron, on: hullID)) {
                guard let entity = entities[id], let drone = entity.kind.drone else { continue }
                let typeID = baseTypeID(of: entity.id) ?? entity.typeID

                var item = FitDocument.Drone(type: typeID, name: names?(typeID))
                if drone.count != drone.squadronSize { item.count = drone.count }
                if drone.flags.isActive { item.active = true }
                if drone.flags.isKamikaze { item.kamikaze = true }
                if drone.target != .invalid,
                   let index = pilots.firstIndex(of: drone.target.pilot) {
                    item.target = index
                }
                item.mutation = exportMutation(of: entity, names: names)
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Mutations

    /// Rolls equal to the base value are omitted: an unrolled item has an empty list.
    private func exportMutation(of entity: Entity,
                                names: (@Sendable (TypeID) -> String?)?) -> FitDocument.Mutation? {
        guard entity.mutation != nil, let mutaplasmidID = mutaplasmidTypeID(of: entity.id) else {
            return nil
        }
        var rolls: [FitDocument.Mutation.Roll] = []
        forEachRoll(of: entity.id) { roll in
            guard roll.value != roll.baseValue else { return }
            rolls.append(.init(attribute: roll.attributeID, value: roll.value))
        }
        rolls.sort { $0.attribute.rawValue < $1.attribute.rawValue }
        return FitDocument.Mutation(mutaplasmid: item(mutaplasmidID, names), rolls: rolls)
    }

    private func item(_ typeID: TypeID,
                      _ names: (@Sendable (TypeID) -> String?)?) -> FitDocument.Item {
        FitDocument.Item(typeID, name: names?(typeID))
    }
}
