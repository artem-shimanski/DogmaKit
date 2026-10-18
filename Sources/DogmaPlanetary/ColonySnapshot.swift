//
//  ColonySnapshot.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// Input to the colony model: layout and pin state at the snapshot moment.
///
/// The target does not know where the data came from; networking, caching and the response format stay with the
/// consumer. The type deliberately mirrors the MEANING of the ESI fields (`GET /characters/{id}/planets` +
/// `/planets/{planet_id}`) so mapping is line by line, but it uses engine types (`TypeID`, `SchematicID`, `Date`)
/// and assumes nothing about JSON.
///
/// Anything ESI may omit is optional; interpreting it (is a cycle running, which ECU cycle is current) is up to
/// `Colony.init(snapshot:catalog:)`, not the consumer.
public struct ColonySnapshot: Hashable, Sendable {
    /// The moment `contents` and pin `lastCycleStart` correspond to. In ESI this is `last_update` from the colony
    /// LIST (the layout does not contain it): the server recomputes the data only when the colony is viewed in the client.
    public var snapshotTime: Date
    /// Planet type ID (11 Temperate, 12 Ice, 13 Gas, 2014 Oceanic, 2015 Lava, 2016 Barren, 2017 Storm, 2063 Plasma).
    /// `nil` skips checking pins against the planet.
    public var planetTypeID: TypeID?
    /// 0...5 (`upgrade_level`).
    public var upgradeLevel: Int
    /// Planet radius, meters (`radius` in the SDE `mapPlanets` / `/universe/planets/{id}`). Needed only by the planner
    /// for link length; without it link cost is not computed.
    public var planetRadius: Double?
    public var pins: [Pin]
    public var routes: [Route]
    public var links: [Link]

    public init(snapshotTime: Date, planetTypeID: TypeID? = nil, upgradeLevel: Int = 0, planetRadius: Double? = nil,
                pins: [Pin] = [], routes: [Route] = [], links: [Link] = []) {
        self.snapshotTime = snapshotTime
        self.planetTypeID = planetTypeID
        self.upgradeLevel = upgradeLevel
        self.planetRadius = planetRadius
        self.pins = pins
        self.routes = routes
        self.links = links
    }

    public struct Pin: Hashable, Sendable {
        /// External pin identifier (`pin_id`); unique within the colony.
        public var pinID: Int64
        public var typeID: TypeID
        /// Radians, as in ESI. This is the polar angle from the north pole (0...pi, the equator is pi/2), not a geographic latitude.
        public var latitude: Double
        /// Radians.
        public var longitude: Double
        /// The processor's schematic (`factory_details.schematic_id`, or `schematic_id`).
        public var schematicID: SchematicID?
        public var installTime: Date?
        public var expiryTime: Date?
        public var lastCycleStart: Date?
        public var contents: [Inventory.Item]
        /// ECU only.
        public var extractor: Extractor?

        public init(pinID: Int64, typeID: TypeID, latitude: Double = 0, longitude: Double = 0,
                    schematicID: SchematicID? = nil, installTime: Date? = nil, expiryTime: Date? = nil,
                    lastCycleStart: Date? = nil, contents: [Inventory.Item] = [], extractor: Extractor? = nil) {
            self.pinID = pinID
            self.typeID = typeID
            self.latitude = latitude
            self.longitude = longitude
            self.schematicID = schematicID
            self.installTime = installTime
            self.expiryTime = expiryTime
            self.lastCycleStart = lastCycleStart
            self.contents = contents
            self.extractor = extractor
        }
    }

    /// `extractor_details`.
    public struct Extractor: Hashable, Sendable {
        public var productTypeID: TypeID?
        /// Seconds.
        public var cycleTime: Int?
        public var quantityPerCycle: Int?
        public var headCount: Int

        public init(productTypeID: TypeID? = nil, cycleTime: Int? = nil, quantityPerCycle: Int? = nil, headCount: Int = 0) {
            self.productTypeID = productTypeID
            self.cycleTime = cycleTime
            self.quantityPerCycle = quantityPerCycle
            self.headCount = headCount
        }
    }

    public struct Route: Hashable, Sendable {
        public var routeID: Int64
        public var sourcePinID: Int64
        public var destinationPinID: Int64
        public var typeID: TypeID
        public var quantity: Double
        public var waypoints: [Int64]

        public init(routeID: Int64, sourcePinID: Int64, destinationPinID: Int64, typeID: TypeID,
                    quantity: Double = 0, waypoints: [Int64] = []) {
            self.routeID = routeID
            self.sourcePinID = sourcePinID
            self.destinationPinID = destinationPinID
            self.typeID = typeID
            self.quantity = quantity
            self.waypoints = waypoints
        }
    }

    public struct Link: Hashable, Sendable {
        public var sourcePinID: Int64
        public var destinationPinID: Int64
        public var level: Int

        public init(sourcePinID: Int64, destinationPinID: Int64, level: Int = 0) {
            self.sourcePinID = sourcePinID
            self.destinationPinID = destinationPinID
            self.level = level
        }
    }
}
