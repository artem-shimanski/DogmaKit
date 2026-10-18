//
//  FitStats+Pilot.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

extension FitStats {

    /// Read-only view of pilot attributes (the `charID` domain in the SDE), e.g. probe
    /// scanning strength, which lives on the pilot rather than the hull.
    public struct Pilot: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: PilotID
        public let attributes: EntityAttributes

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: PilotID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }

        public var hull: Hull {
            @_lifetime(borrow self)
            get { Hull(session: session, id: id.hull) }
        }

        public var skills: Skills {
            @_lifetime(borrow self)
            get { Skills(pilot: self) }
        }

        public var implants: Implants {
            @_lifetime(borrow self)
            get { Implants(pilot: self) }
        }

        public var boosters: Boosters {
            @_lifetime(borrow self)
            get { Boosters(pilot: self) }
        }

        /// Probe scan strength (`baseSensorStrength`), including probe launchers, scanning
        /// rigs, implants and Astrometrics skills.
        public var probeScanStrength: Double {
            attributes[.baseSensorStrength] ?? 0
        }
    }
}
