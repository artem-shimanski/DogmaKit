//
//  FitDocument+Import.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

import DogmaModels

extension Fit {

    /// Replays the document through the write API. Nothing is cleared: the document is
    /// appended to the session's current contents.
    ///
    /// Targets are resolved in a second pass, since they can refer to later pilots.
    ///
    /// - Parameter strict: if `false` (default), warnings are collected and returned;
    ///   if `true`, the first warning is thrown.
    @discardableResult
    public func load(_ document: FitDocument,
                     strict: Bool = false) throws(FitDocument.Warning) -> [FitDocument.Warning] {
        var warnings: [FitDocument.Warning] = []

        func report(_ warning: FitDocument.Warning) throws(FitDocument.Warning) {
            if strict { throw warning }
            warnings.append(warning)
        }

        if document.format != FitDocument.formatIdentifier {
            try report(.unknownFormat(document.format))
        }
        if document.version > FitDocument.currentVersion {
            try report(.unsupportedVersion(document.version))
        }

        for item in document.environment {
            do {
                try environment.add(item.type)
            } catch {
                try report(.typeRejected(item.type, error))
            }
        }

        // Exceeding the pilot limit is an impossible document, not data loss: throw in
        // either mode, before any mutation.
        if pilots.count + document.pilots.count > Pilots.maxCount {
            throw .pilotRejected(index: Pilots.maxCount - pilots.count, .pilotLimitExceeded)
        }

        // Target addresses: pilot index in the document → its hull.
        var hulls: [HullID] = []
        // Deferred targets, resolved once all pilots exist.
        var moduleTargets: [(ModuleID, Int)] = []
        var droneTargets: [(DroneID, Int)] = []

        for (index, pilotDocument) in document.pilots.enumerated() {
            let level = pilotDocument.skills?.default ?? 0
            let pilotID: PilotID
            do {
                pilotID = try pilots.add(skillLevel: level).id
            } catch {
                if case .pilotLimitExceeded = error { throw .pilotRejected(index: index, error) }
                try report(.pilotRejected(index: index, error))
                continue
            }
            hulls.append(pilotID.hull)

            let pilot = self[pilotID]

            for skill in pilotDocument.skills?.levels ?? [] {
                guard session.pointee.skillIDMap?[skill.type] != nil else {
                    try report(.skillNotFound(skill.type))
                    continue
                }
                pilot.skills[typeID: skill.type]?.level = skill.level
            }

            for item in pilotDocument.implants {
                do { try pilot.implants.add(item.type) }
                catch { try report(.typeRejected(item.type, error)) }
            }
            for item in pilotDocument.boosters {
                do { try pilot.boosters.add(item.type) }
                catch { try report(.typeRejected(item.type, error)) }
            }

            guard let shipDocument = pilotDocument.ship else { continue }
            let hull = pilot.hull
            do {
                try hull.set(typeID: shipDocument.type)
            } catch {
                try report(.typeRejected(shipDocument.type, error))
                continue
            }

            for moduleDocument in shipDocument.modules {
                guard let moduleID = try loadModule(moduleDocument, on: hull, report: report) else {
                    continue
                }
                if let target = moduleDocument.target {
                    moduleTargets.append((moduleID, target))
                }
            }
            for droneDocument in shipDocument.drones {
                guard let droneID = try loadDrone(droneDocument, on: hull, report: report) else {
                    continue
                }
                if let target = droneDocument.target {
                    droneTargets.append((droneID, target))
                }
            }
        }

        // Second pass: targets.
        for (moduleID, index) in moduleTargets {
            guard hulls.indices.contains(index) else {
                try report(.targetOutOfRange(index))
                continue
            }
            let module = self[moduleID]
            module.target = hulls[index]
        }
        for (droneID, index) in droneTargets {
            guard hulls.indices.contains(index) else {
                try report(.targetOutOfRange(index))
                continue
            }
            let drone = self[droneID]
            drone.target = hulls[index]
        }

        return warnings
    }

    // MARK: - Module

    private func loadModule(_ document: FitDocument.Module,
                            on hull: borrowing Hull,
                            report: (FitDocument.Warning) throws(FitDocument.Warning) -> Void
    ) throws(FitDocument.Warning) -> ModuleID? {
        let modules = hull.modules
        let moduleID: ModuleID
        do {
            // `type` is always the base type; the abyssal type is derived from the mutaplasmid.
            if let mutation = document.mutation {
                moduleID = try modules.add(document.type, mutaplasmid: mutation.mutaplasmid.type).id
            } else {
                moduleID = try modules.add(document.type).id
            }
        } catch {
            if let mutation = document.mutation {
                try report(.mutationRejected(mutation.mutaplasmid.type, on: document.type, error))
            } else {
                try report(.typeRejected(document.type, error))
            }
            return nil
        }

        let module = self[moduleID]
        if let socket = document.socket {
            module.socket = socket
        }
        if let state = document.state {
            module.state = state.state
        }
        if let charge = document.charge {
            do { try module.setCharge(charge.type) }
            catch { try report(.chargeRejected(charge.type, to: document.type, error)) }
        }
        for roll in document.mutation?.rolls ?? [] {
            do { try module.setRoll(roll.value, for: roll.attribute) }
            catch { try report(.rollRejected(roll.attribute, on: document.type, error)) }
        }
        return moduleID
    }

    // MARK: - Drone

    private func loadDrone(_ document: FitDocument.Drone,
                           on hull: borrowing Hull,
                           report: (FitDocument.Warning) throws(FitDocument.Warning) -> Void
    ) throws(FitDocument.Warning) -> DroneID? {
        let drones = hull.drones
        let droneID: DroneID
        do {
            if let mutation = document.mutation {
                droneID = try drones.add(document.type,
                                         mutaplasmid: mutation.mutaplasmid.type,
                                         count: document.count).id
            } else {
                droneID = try drones.add(document.type, count: document.count).id
            }
        } catch {
            if let mutation = document.mutation {
                try report(.mutationRejected(mutation.mutaplasmid.type, on: document.type, error))
            } else {
                try report(.typeRejected(document.type, error))
            }
            return nil
        }

        let drone = self[droneID]
        if document.active == true { drone.isActive = true }
        if document.kamikaze == true {
            // The setter silently ignores types without the ability; report it.
            drone.isKamikaze = true
            if !drone.isKamikaze {
                try report(.valueClamped(document.type, "kamikaze"))
            }
        }
        for roll in document.mutation?.rolls ?? [] {
            do { try drone.setRoll(roll.value, for: roll.attribute) }
            catch { try report(.rollRejected(roll.attribute, on: document.type, error)) }
        }
        return droneID
    }
}

// MARK: - Engine conveniences

extension DogmaEngine {

    /// Loads the document into an empty session, replacing all contents.
    /// To append to an existing fit use `edit { try $0.load(document) }`.
    @discardableResult
    public func load(_ document: FitDocument,
                     strict: Bool = false) throws(FitDocument.Warning) -> [FitDocument.Warning] {
        session.entities = EntityStore()
        session.invalidate()
        return try withUnsafeMutablePointer(to: &session) { (ptr) throws(FitDocument.Warning) in
            try Fit(session: ptr).load(document, strict: strict)
        }
    }
}
