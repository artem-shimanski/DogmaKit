//
//  ColonyFitting.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// Layout check for a colony planner: command center CPU/PG, link cost, route connectivity, ECU head limit.
///
/// Not needed for forecasting (a colony from the game is valid by definition). Useful when a layout is edited
/// (`Colony.snapshot()` -> edit -> `Colony.init(snapshot:catalog:)`). Nothing is forbidden: as with ship fitting,
/// overload is reported in `issues`, not thrown.
public struct ColonyFitting: Hashable, Sendable {

    public struct Usage: Hashable, Sendable {
        public var used: Double
        public var total: Double
        public var free: Double { total - used }
        public var isOverloaded: Bool { used > total }
    }

    public struct PinLoad: Hashable, Sendable {
        public var pin: Colony.PinIndex
        public var cpu: Double
        public var power: Double
    }

    public struct LinkLoad: Hashable, Sendable {
        /// Index into `Colony.links`.
        public var link: Int
        /// Surface length, km; `nil` if the planet radius is unknown.
        public var length: Double?
        public var cpu: Double
        public var power: Double
    }

    public enum Issue: Hashable, Sendable {
        case noCommandCenter
        case multipleCommandCenters(count: Int)
        /// `upgradeLevel` is outside the catalog's level table; command center resources are taken as zero.
        case invalidUpgradeLevel(Int)
        case cpuOverloaded
        case powerOverloaded
        /// More heads than an ECU allows (10).
        case tooManyHeads(Colony.PinIndex, count: Int)
        /// A route path (source -> waypoints -> destination) crosses a place with no link.
        case routeNotLinked(routeID: Int64)
        /// Planet radius is not set: link length and cost were computed without the length term (base load only).
        case linkLengthUnknown
    }

    public var cpu: Usage
    public var power: Usage
    public var pins: [PinLoad]
    public var links: [LinkLoad]
    public var issues: [Issue]

    /// Maximum number of ECU heads.
    public static let maxExtractorHeads = 10
}

extension Colony {

    /// Resources and validity of the layout (see `ColonyFitting`).
    ///
    /// A pin's load is `cpuLoad`/`powerLoad` of its type; an ECU adds head load times head count. Resources come
    /// from the catalog's command center level table by `upgradeLevel` (the command center itself has no load).
    ///
    /// Link load: `base + perKm * length * (level + 1)^levelModifier` (attributes 1635/1636: 1.4 CPU, 1.2 PG).
    /// Only the length-dependent part grows with level, and the modifier is an EXPONENT. Each link's load is
    /// rounded up to an integer before summing.
    /// Length is the great-circle arc at the planet radius. ESI `latitude` is NOT a geographic latitude but the
    /// polar angle from the north pole (0...pi), hence `sin` rather than `cos` in the formula.
    public var fitting: ColonyFitting {
        var issues: [ColonyFitting.Issue] = []
        var pinLoads: [ColonyFitting.PinLoad] = []
        var cpuUsed = 0.0
        var powerUsed = 0.0
        var commandCenters = 0

        for pin in pins {
            guard let info = catalog.pin(pin.typeID) else { continue }
            var cpu = info.cpuLoad
            var power = info.powerLoad
            if info.kind == .commandCenter { commandCenters += 1 }
            if case .extractor(let extractor) = pin.role {
                cpu += info.extractorHeadCPU * Double(extractor.headCount)
                power += info.extractorHeadPower * Double(extractor.headCount)
                if extractor.headCount > ColonyFitting.maxExtractorHeads {
                    issues.append(.tooManyHeads(pin.id, count: extractor.headCount))
                }
            }
            pinLoads.append(.init(pin: pin.id, cpu: cpu, power: power))
            cpuUsed += cpu
            powerUsed += power
        }

        if commandCenters == 0 { issues.append(.noCommandCenter) }
        if commandCenters > 1 { issues.append(.multipleCommandCenters(count: commandCenters)) }

        let link = catalog.link
        var linkLoads: [ColonyFitting.LinkLoad] = []
        if planetRadius == nil, !links.isEmpty { issues.append(.linkLengthUnknown) }
        for (offset, l) in links.enumerated() {
            let length = linkLength(l)
            let cpuFactor = pow(Double(l.level + 1), link.cpuLoadLevelModifier)
            let powerFactor = pow(Double(l.level + 1), link.powerLoadLevelModifier)
            let cpu = Self.roundUp(link.cpuLoad + link.cpuLoadPerKm * (length ?? 0) * cpuFactor)
            let power = Self.roundUp(link.powerLoad + link.powerLoadPerKm * (length ?? 0) * powerFactor)
            linkLoads.append(.init(link: offset, length: length, cpu: cpu, power: power))
            cpuUsed += cpu
            powerUsed += power
        }

        let resources = commandCenters > 0 ? catalog.commandCenter(level: upgradeLevel) : nil
        if commandCenters > 0, resources == nil {
            issues.append(.invalidUpgradeLevel(upgradeLevel))
        }
        let cpu = ColonyFitting.Usage(used: cpuUsed, total: resources?.cpu ?? 0)
        let power = ColonyFitting.Usage(used: powerUsed, total: resources?.power ?? 0)
        if cpu.isOverloaded { issues.append(.cpuOverloaded) }
        if power.isOverloaded { issues.append(.powerOverloaded) }

        // Route connectivity: every step of the path must follow a link (in either direction).
        var linked = Set<[UInt16]>()
        for l in links {
            linked.insert([l.source.rawValue, l.destination.rawValue].sorted())
        }
        for route in routes {
            let path = [route.source] + route.waypoints + [route.destination]
            let ok = zip(path, path.dropFirst()).allSatisfy { linked.contains([$0.rawValue, $1.rawValue].sorted()) }
            if !ok { issues.append(.routeNotLinked(routeID: route.routeID)) }
        }

        return ColonyFitting(cpu: cpu, power: power, pins: pinLoads, links: linkLoads, issues: issues)
    }

    /// `ceil` that leaves integers corrupted by `Double` error alone (`15.000000000001` -> 15).
    static func roundUp(_ value: Double) -> Double {
        (value - 1e-9).rounded(.up)
    }

    /// Link length along the surface, km.
    func linkLength(_ link: Link) -> Double? {
        guard let radius = planetRadius else { return nil }
        let a = self[link.source]
        let b = self[link.destination]
        let dLat = b.latitude - a.latitude
        let dLon = b.longitude - a.longitude
        // latitude is the polar angle theta, so cos(latitude) = sin(theta).
        let h = sin(dLat / 2) * sin(dLat / 2) + sin(a.latitude) * sin(b.latitude) * sin(dLon / 2) * sin(dLon / 2)
        let angle = 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
        return radius / 1000 * angle
    }
}
