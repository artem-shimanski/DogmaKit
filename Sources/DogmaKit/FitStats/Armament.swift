//
//  Armament.swift
//  DogmaKit
//

/// All weapons of a hull: damaging modules in hi/med/low racks and every channel of its
/// drones and fighters. Hull damage totals are pure functions of it. See
/// `FitStats.Hull.armament`.
public struct Armament: Sendable, Hashable {

    public struct Entry: Sendable, Hashable {
        /// Category for the `from:` filter of `dps(from:to:)` / `volleyDamage(from:to:)`.
        public var source: FitStats.Hull.DamageSource
        /// The module or drone that fires the weapon.
        public var entityID: EntityID
        /// The drone channel; `nil` for modules.
        public var channel: FitStats.Drone.Channel?
        public var weapon: Weapon

        public init(source: FitStats.Hull.DamageSource,
                    entityID: EntityID,
                    channel: FitStats.Drone.Channel? = nil,
                    weapon: Weapon) {
            self.source = source
            self.entityID = entityID
            self.channel = channel
            self.weapon = weapon
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Total DPS from the given source categories. `target == .zero` gives raw DPS with no
    /// tracking, range or missile flight penalties.
    public func dps(from sources: FitStats.Hull.DamageSource = .all,
                    to target: Target = .zero) -> DamageVector {
        var result = DamageVector.zero
        for entry in entries where sources.contains(entry.source) {
            result += entry.weapon.dps(to: target)
        }
        return result
    }

    /// Total volley (alpha strike) from the given source categories: damage of one cycle
    /// of every weapon fired at once.
    public func volleyDamage(from sources: FitStats.Hull.DamageSource = .all,
                             to target: Target = .zero) -> DamageVector {
        var result = DamageVector.zero
        for entry in entries where sources.contains(entry.source) {
            result += entry.weapon.volleyDamage(to: target)
        }
        return result
    }
}
