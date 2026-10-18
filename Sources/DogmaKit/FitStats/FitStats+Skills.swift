//
//  FitStats+Skills.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The pilot's skills, read-only. Mirrors `Fit.Skills` without the write members.
    public struct Skills: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        @usableFromInline internal let pilotID: PilotID

        @inlinable
        @_lifetime(borrow pilot)
        init(pilot: borrowing Pilot) {
            self.session = pilot.session
            self.pilotID = pilot.id
        }

        @inlinable
        public var allIDs: some Sequence<SkillID> {
            session.pointee.entities.ids(in: .skill(for: pilotID.rawValue)).as(SkillID.self)
        }

        @inlinable
        public subscript(id: SkillID) -> Skill {
            @_lifetime(copy self) get {
                _overrideLifetime(Skill(session: session, id: id), copying: self)
            }
        }

        @inlinable
        public subscript(typeID typeID: TypeID) -> Skill? {
            @_lifetime(copy self) get {
                guard let index = session.pointee.skillIDMap?[typeID] else { return nil }
                let skillID = SkillID(rawValue: EntityID.skill(index, for: pilotID.rawValue))
                let skill = Skill(session: session, id: skillID)
                return _overrideLifetime(skill, copying: self)
            }
        }

        public func forEach(_ body: (borrowing Skill) -> Void) {
            for id in allIDs {
                body(Skill(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }
    }
}
