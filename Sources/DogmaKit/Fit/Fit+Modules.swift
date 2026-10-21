//
//  Fit+Modules.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    /// The hull's modules, writable.
    ///
    /// All collections (`Fit.Pilots`, `Fit.Modules`, `Fit.Drones`, `Fit.Skills`,
    /// `Fit.Implants`, `Fit.Boosters` and their `FitStats` mirrors) share the same members:
    /// - `allIDs`: all IDs;
    /// - `ids(in:)`: IDs by domain key (slot / squadron) when a key maps to several elements;
    /// - `subscript(_:)`: element by ID;
    /// - `subscript(slot:)` / `subscript(typeID:)`: element by a unique domain key;
    /// - `forEach(_:)` / `forEach(in:_:)`: iteration;
    /// - `count` / `count(in:)`: counts;
    /// - `add(...)`: write path only.
    public struct Modules: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        @usableFromInline internal let hullID: HullID

        @inlinable
        internal var hullEntity: Entity {
            session.pointee.entities[hullID.rawValue]!
        }

        @inlinable
        @_lifetime(borrow hull)
        init(hull: borrowing Hull) {
            self.session = hull.session
            self.hullID = hull.id
        }

        // MARK: - Reading

        @inlinable
        public var allIDs: some Sequence<ModuleID> {
            session.pointee.entities.modules(on: hullID.rawValue).as(ModuleID.self)
        }

        @inlinable
        public func ids(in slot: Entity.Module.Slot) -> some Sequence<ModuleID> {
            session.pointee.entities.ids(in: .module(in: slot, on: hullID.rawValue)).as(ModuleID.self)
        }

        @inlinable
        public subscript(id: ModuleID) -> Module {
            @_lifetime(copy self) get {
                _overrideLifetime(Module(session: session, id: id), copying: self)
            }
        }

        public func forEach(_ body: (borrowing Module) -> Void) {
            for id in allIDs {
                body(Module(session: session, id: id))
            }
        }

        public func forEach(in slot: Entity.Module.Slot, _ body: (borrowing Module) -> Void) {
            for id in ids(in: slot) {
                body(Module(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }

        public func count(in slot: Entity.Module.Slot) -> Int {
            ids(in: slot).count()
        }

        /// Mask of occupied sockets in a rack. Sockets beyond `socketCount` are not included.
        private func occupiedSockets(in slot: Entity.Module.Slot) -> UInt64 {
            var mask: UInt64 = 0
            for id in session.pointee.entities.ids(in: .module(in: slot, on: hullID.rawValue)) {
                guard let socket = session.pointee.entities[id]?.kind.module?.socket,
                      socket < Entity.Module.socketCount else { continue }
                mask |= 1 << UInt64(socket)
            }
            return mask
        }

        /// First free socket of a rack. A rack holds at most 63 modules, so a free bit always exists.
        private func firstFreeSocket(in slot: Entity.Module.Slot) -> UInt8 {
            UInt8(truncatingIfNeeded: (~occupiedSockets(in: slot)).trailingZeroBitCount)
        }

        // MARK: - Writing

        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID) throws(DogmaError) -> Module {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let moduleID = try append(info, base: nil, mutation: nil)
            let module = Module(session: session, id: moduleID)
            return _overrideLifetime(module, copying: self)
        }

        /// Adds a mutated (abyssal) module. `typeID` is the base type; the resulting type
        /// is derived from the mutaplasmid. Rolls start at the base values (multiplier 1.0);
        /// set them with `Fit.Module.setRoll`.
        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID, mutaplasmid mutaplasmidID: TypeID) throws(DogmaError) -> Module {
            let sde = session.pointee.sde
            guard let mutaplasmid = sde.mutaplasmid(mutaplasmidID) else {
                throw DogmaError.mutaplasmidNotFound(mutaplasmidID)
            }
            guard mutaplasmid.applicableTypes.contains(typeID) else {
                throw DogmaError.mutaplasmidNotApplicable(mutaplasmidID, to: typeID)
            }
            guard let base = sde[typeID] else { throw DogmaError.typeNotFound(typeID) }

            let resultingTypeID = mutaplasmid.resultingTypeID.load()
            guard let info = sde[resultingTypeID] else { throw DogmaError.typeNotFound(resultingTypeID) }

            let mutation = Mutation(mutaplasmid: mutaplasmid.reference, baseType: base.reference)
            let moduleID = try append(info, base: base, mutation: mutation)
            session.pointee.entities.resetRolls(on: moduleID.rawValue, using: sde)
            let module = Module(session: session, id: moduleID)
            return _overrideLifetime(module, copying: self)
        }

        /// Shared body of both `add` methods. Checks use the merged data (resulting type
        /// with fallback to the base type), see `Mutation`.
        private func append(_ info: DogmaSDE.TypeInfo.View,
                            base: DogmaSDE.TypeInfo.View?,
                            mutation: Mutation?) throws(DogmaError) -> ModuleID {
            let hullEntity = self.hullEntity
            let sde = session.pointee.sde
            let typeID = info.id.load()
            let groupID = info.groupID.load()
            let categoryID = info.categoryID.load()

            // T3C subsystems are a separate SDE category but fit like modules into `.subsystem`.
            if hullEntity.categoryID == .ship && categoryID != .module && categoryID != .subsystem {
                throw DogmaError.invalidCategory(categoryID, expected: [.module, .subsystem])
            }
            else if hullEntity.categoryID == .structure && categoryID != .structureModule {
                throw DogmaError.invalidCategory(categoryID, expected: [.structureModule])
            }

            var module = try Entity.Module(info, base: base)

            // Slot-specific checks run before `canFit` to report a more precise reason.
            // No effect modifies rigSize/subSystemSlot/maxSubSystems, so base type values are compared.
            switch module.slot {
            case .rig:
                // Rig size must match the hull. Raw values are compared so that an unknown
                // future size does not collapse to `.none` and fit hulls without a rig size.
                let hullSize = Double(sde[hullEntity.info].attributes[.rigSize]?.load() ?? 0)
                let rigSize = Double(typeAttribute(.rigSize, of: info, base: base) ?? 0)
                guard rigSize == hullSize else {
                    throw DogmaError.rigSizeMismatch(typeID,
                                                     expected: RigSize(hullSize),
                                                     actual: RigSize(rigSize))
                }

            case .subsystem:
                // The hull must accept subsystems...
                guard (sde[hullEntity.info].attributes[.maxSubSystems]?.load() ?? 0) > 0 else {
                    throw DogmaError.subsystemsNotSupported(by: hullEntity.typeID)
                }
                // ...and the subsystem slot (Core/Defensive/Offensive/Propulsion) must be free.
                let subsystemSlot = typeAttribute(.subSystemSlot, of: info, base: base) ?? 0
                for id in ids(in: .subsystem) {
                    guard let other = session.pointee.entities[id.rawValue],
                          (sde[other.info].attributes[.subSystemSlot]?.load() ?? 0) == subsystemSlot
                    else { continue }
                    throw DogmaError.subsystemSlotOccupied(typeID, by: other.typeID)
                }

            default:
                break
            }

            // Abyssal types have no fittingRequirements of their own; use the base type's.
            var canFit = true
            if let requirements = info.fittingRequirements {
                canFit = requirements.canFit(to: sde[hullEntity.info])
            }
            else if let base, let requirements = base.fittingRequirements {
                canFit = requirements.canFit(to: sde[hullEntity.info])
            }
            guard canFit else { throw DogmaError.cantFit(typeID, to: hullEntity.typeID) }

            // Position in the rack: the first free socket, so a freed index is reused.
            module.socket = firstFreeSocket(in: module.slot)

            let entity = try session.pointee.entities.append(in: .module(in: module.slot, on: hullEntity.id)) { id in
                Entity(id: id,
                       typeID: typeID,
                       groupID: groupID,
                       categoryID: categoryID,
                       info: info.reference,
                       mutation: mutation,
                       kind: .module(module))
            }
            return ModuleID(rawValue: entity)
        }
    }
}
