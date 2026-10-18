//
//  FitStats+Modules.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The hull's modules, read-only. Mirrors `Fit.Modules` without the write members:
    /// `allIDs`, `ids(in:)`, `subscript(_:)`, `forEach(_:)`, `forEach(in:_:)`,
    /// `count`, `count(in:)`.
    public struct Modules: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        @usableFromInline internal let hullID: HullID

        @inlinable
        @_lifetime(borrow hull)
        init(hull: borrowing Hull) {
            self.session = hull.session
            self.hullID = hull.id
        }

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
    }
}
