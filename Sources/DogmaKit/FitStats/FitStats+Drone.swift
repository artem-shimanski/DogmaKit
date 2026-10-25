//
//  FitStats+Drone.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 24.07.2026.
//

import Foundation

extension FitStats {
    /// Read-only view of a drone or fighter stack. Unlike modules, drones have no state
    /// machine, only `isActive` (deployed in space).
    @Snapshottable
    public struct Drone: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: DroneID
        @inlinable var entityID: EntityID {id.rawValue}
        @SnapshotIgnored public let attributes: EntityAttributes

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: DroneID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }

        @inlinable
        var entity: Entity {
            session.pointee.entities[entityID]!
        }

        @inlinable
        public var typeID: TypeID {
            entity.typeID
        }

        /// Drones can always be targeted; mirrors `FitStats.Module.isProjectable`.
        public var isProjectable: Bool { true }

        public var squadron: Entity.Drone.Squadron {
            entity.kind.drone?.squadron ?? .none
        }

        /// Maximum squadron/stack size (5 for drones).
        public var squadronSize: Int {
            Int(entity.kind.drone?.squadronSize ?? 0)
        }

        /// Number of drones in the stack / fighters in the squadron. One entity describes the
        /// whole stack: only additive outputs (damage, mining, neut) are multiplied by `count`.
        public var count: Int {
            Int(entity.kind.drone?.count ?? 1)
        }

        /// Whether the drone or fighter is deployed in space (applies active effects).
        public var isActive: Bool {
            entity.kind.drone?.flags.isActive ?? false
        }

        public var dealsDamage: Bool {
            entity.kind.drone?.flags.dealsDamage ?? false
        }

        /// Whether the drone is mutated (abyssal).
        public var isMutated: Bool {
            entity.mutation != nil
        }

        /// Type ID of the mutaplasmid applied to the drone.
        public var mutaplasmidTypeID: TypeID? {
            session.pointee.mutaplasmidTypeID(of: entityID)
        }

        /// Type ID of the base (unmutated) type.
        public var baseTypeID: TypeID? {
            session.pointee.baseTypeID(of: entityID)
        }

        /// The drone's mutation rolls; empty if it is not mutated.
        public var rolls: [MutationRoll] {
            var rolls: [MutationRoll] = []
            forEachRoll { rolls.append($0) }
            return rolls
        }

        /// Iterates the drone's mutation rolls.
        public func forEachRoll(_ body: (MutationRoll) -> Void) {
            session.pointee.forEachRoll(of: entityID, body)
        }

        /// Whether the type has the kamikaze ability (`fighterAbilityKamikaze`).
        public var hasKamikazeAbility: Bool {
            entity.kind.drone?.flags.hasKamikazeAbility ?? false
        }

        /// Whether kamikaze mode is on. It is exclusive: regular weapons deal no damage and
        /// all damage is a single volley (`kamikazeVolleyDamage`).
        public var isKamikaze: Bool {
            guard let flags = entity.kind.drone?.flags else { return false }
            return flags.isKamikaze && flags.hasKamikazeAbility
        }

        /// The drone's target, normalized to a hull, or `nil`.
        public var target: EntityID? {
            guard let target = entity.kind.drone?.target, target != .invalid,
                  session.pointee.entities.contains(target) else { return nil }
            return target
        }

        @SnapshotNested
        public var charge: Charge? {
            @_lifetime(borrow self)
            get {
                let chargeID = id.charge
                guard session.pointee.entities.contains(chargeID.rawValue) else { return nil }
                return Charge(session: session, id: chargeID)
            }
        }

        /// A weapon channel of a drone or fighter. A regular drone has one (`.drone`);
        /// each fighter ability has its own attributes and cycle time, so DPS is summed per channel.
        public enum Channel: Sendable, Hashable, CaseIterable {
            /// The drone's own weapon: turret (`emDamage`, …) or missile (charge).
            case drone
            /// Fighter "Attack", turret variant (heavy/assault fighters).
            case fighterAttackTurret
            /// Fighter "Attack", missile variant (light fighters).
            case fighterAttackMissile
            /// Fighter "Missiles": heavy missile/torpedo volley.
            case fighterMissiles
            /// Kamikaze detonation. One-shot (the squadron dies), so it counts toward
            /// volley but not sustained DPS.
            case kamikaze

            /// Whether the channel deals repeated damage (`false` for kamikaze).
            public var isSustained: Bool {
                self != .kamikaze
            }
        }

        /// Deployed and not in kamikaze mode. Kamikaze also disables mining and neuts.
        private var isOperating: Bool {
            isActive && !isKamikaze
        }

        /// Whether a channel works in the current state: kamikaze mode enables only
        /// `.kamikaze`, otherwise only the regular channels.
        private func isEnabled(_ channel: Channel) -> Bool {
            guard isActive else { return false }
            return channel == .kamikaze ? isKamikaze : isOperating
        }

        /// Cycle time, seconds (max over duration attributes). Fighter reloads are not modeled.
        public var rawCycleTime: Double {
            Global.droneCycleTimeAttributes.reduce(0.0) { max($0, attributes[$1] ?? 0) } / 1000
        }

        /// Cycle time, seconds. `ReloadPolicy` does not affect drones.
        public func cycleTime() -> Double {
            rawCycleTime
        }

        /// Cycle time of a channel, seconds. Fighter abilities keep their duration in their
        /// own attributes, so `rawCycleTime` is zero for fighters.
        public func cycleTime(of channel: Channel) -> Double {
            switch channel {
            case .drone:
                // The weapon fires at `speed`; drones that also run an effect (Orbweaver: web
                // with `duration`) must not take the longer of the two, as `rawCycleTime` does.
                if let speed = attributes[.speed], speed > 0 {
                    return speed / 1000
                }
                return rawCycleTime
            case .fighterAttackTurret:
                return (attributes[.fighterAbilityAttackTurretDuration] ?? 0) / 1000
            case .fighterAttackMissile:
                return (attributes[.fighterAbilityAttackMissileDuration] ?? 0) / 1000
            case .fighterMissiles:
                return (attributes[.fighterAbilityMissilesDuration] ?? 0) / 1000
            case .kamikaze:
                return (attributes[.fighterAbilityKamikazeDuration] ?? 0) / 1000
            }
        }

        /// Total volley over all working channels: the detonation in kamikaze mode, otherwise
        /// the sum of the regular channels.
        public var volleyDamage: DamageVector {
            guard isActive else { return .zero }
            var result = DamageVector.zero
            for channel in Channel.allCases {
                result += volleyDamage(of: channel)
            }
            return result
        }

        /// Volley of one channel, already multiplied by `count`. Zero if the channel does
        /// not work in the current state.
        public func volleyDamage(of channel: Channel) -> DamageVector {
            guard isEnabled(channel) else { return .zero }
            return rawVolleyDamage(of: channel)
        }

        /// Stack volley of the `.drone` channel. Damage comes from the charge if there is one,
        /// otherwise from the drone itself; multiplied by `count`.
        public var droneVolleyDamage: DamageVector {
            volleyDamage(of: .drone)
        }

        /// Detonation damage of the whole squadron. Non-zero only in kamikaze mode; a one-shot
        /// volley, not DPS.
        public var kamikazeVolleyDamage: DamageVector {
            volleyDamage(of: .kamikaze)
        }

        public var fighterAttackMissileVolleyDamage: DamageVector {
            volleyDamage(of: .fighterAttackMissile)
        }

        public var fighterMissileVolleyDamage: DamageVector {
            volleyDamage(of: .fighterMissiles)
        }

        public var fighterAttackTurretVolleyDamage: DamageVector {
            volleyDamage(of: .fighterAttackTurret)
        }

        /// Volley of one channel regardless of state, multiplied by `count`; zero for
        /// channels the type does not have.
        private func rawVolleyDamage(of channel: Channel) -> DamageVector {
            func damage(_ em: AttributeID, _ thermal: AttributeID,
                        _ kinetic: AttributeID, _ explosive: AttributeID,
                        multiplier: AttributeID?) -> DamageVector {
                let volley = DamageVector(em: attributes[em] ?? 0,
                                          thermal: attributes[thermal] ?? 0,
                                          kinetic: attributes[kinetic] ?? 0,
                                          explosive: attributes[explosive] ?? 0)
                let factor = multiplier.flatMap { attributes[$0] } ?? 0
                return (factor > 0 ? volley * factor : volley) * Double(count)
            }

            switch channel {
            case .drone:
                func damage(with attributes: EntityAttributes) -> DamageVector {
                    DamageVector(em: attributes[.emDamage] ?? 0,
                                 thermal: attributes[.thermalDamage] ?? 0,
                                 kinetic: attributes[.kineticDamage] ?? 0,
                                 explosive: attributes[.explosiveDamage] ?? 0)
                }
                let volley: DamageVector
                if let charge {
                    volley = damage(with: charge.attributes)
                }
                else {
                    volley = damage(with: attributes)
                }
                let multiplier = max(attributes[.damageMultiplier] ?? 0, attributes[.missileDamageMultiplier] ?? 0)
                return (multiplier > 0 ? volley * multiplier : volley) * Double(count)
            case .fighterAttackTurret:
                return damage(.fighterAbilityAttackTurretDamageEM, .fighterAbilityAttackTurretDamageTherm,
                              .fighterAbilityAttackTurretDamageKin, .fighterAbilityAttackTurretDamageExp,
                              multiplier: .fighterAbilityAttackTurretDamageMultiplier)
            case .fighterAttackMissile:
                return damage(.fighterAbilityAttackMissileDamageEM, .fighterAbilityAttackMissileDamageTherm,
                              .fighterAbilityAttackMissileDamageKin, .fighterAbilityAttackMissileDamageExp,
                              multiplier: .fighterAbilityAttackMissileDamageMultiplier)
            case .fighterMissiles:
                return damage(.fighterAbilityMissilesDamageEM, .fighterAbilityMissilesDamageTherm,
                              .fighterAbilityMissilesDamageKin, .fighterAbilityMissilesDamageExp,
                              multiplier: .fighterAbilityMissilesDamageMultiplier)
            case .kamikaze:
                return damage(.fighterAbilityKamikazeDamageEM, .fighterAbilityKamikazeDamageTherm,
                              .fighterAbilityKamikazeDamageKin, .fighterAbilityKamikazeDamageExp,
                              multiplier: nil)
            }
        }

        // MARK: - Range and tracking

        /// Optimal range of a channel. For `.drone`, as for modules: the first positive
        /// attribute from `Global.optimalAttributes`, otherwise the built-in missile's flight range.
        public func optimal(of channel: Channel) -> Double {
            switch channel {
            case .drone:
                for attributeID in Global.optimalAttributes {
                    if let value = attributes[attributeID], value > 0 {
                        return value
                    }
                }
                guard let charge else { return 0 }
                return missileFlightRange(charge: charge)
            case .fighterAttackTurret:
                return attributes[.fighterAbilityAttackTurretRangeOptimal] ?? 0
            case .fighterAttackMissile:
                return attributes[.fighterAbilityAttackMissileRangeOptimal] ?? 0
            case .fighterMissiles:
                return attributes[.fighterAbilityMissilesRange] ?? 0
            case .kamikaze:
                return attributes[.fighterAbilityKamikazeRange] ?? 0
            }
        }

        /// Falloff of a channel. `0` means no falloff.
        public func falloff(of channel: Channel) -> Double {
            switch channel {
            case .drone:
                for attributeID in Global.falloffAttributes {
                    if let value = attributes[attributeID], value > 0 {
                        return value
                    }
                }
                return 0
            case .fighterAttackTurret:
                return attributes[.fighterAbilityAttackTurretRangeFalloff] ?? 0
            case .fighterAttackMissile:
                return attributes[.fighterAbilityAttackMissileRangeFalloff] ?? 0
            case .fighterMissiles, .kamikaze:
                return 0
            }
        }

        /// Tracking speed of a channel. `0` for non-turret channels.
        public func accuracyScore(of channel: Channel) -> Double {
            switch channel {
            case .drone: return attributes[.trackingSpeed, default: .sde]
            case .fighterAttackTurret: return attributes[.fighterAbilityAttackTurretTrackingSpeed] ?? 0
            case .fighterAttackMissile, .fighterMissiles, .kamikaze: return 0
            }
        }

        /// Signature resolution of a turret channel.
        public func signatureResolution(of channel: Channel) -> Double {
            switch channel {
            case .drone: return attributes[.optimalSigRadius, default: .sde]
            case .fighterAttackTurret: return attributes[.fighterAbilityAttackTurretSignatureResolution] ?? 0
            case .fighterAttackMissile, .fighterMissiles, .kamikaze: return 0
            }
        }

        /// Flight range of the drone's built-in missile, including its multipliers.
        func missileFlightRange(charge: borrowing Charge) -> Double {
            let velocityMultiplier = attributes[.missileEntityVelocityMultiplier, default: .sde]
            let flightTimeMultiplier = attributes[.missileEntityFlightTimeMultiplier, default: .sde]

            return WeaponMath.missileFlightRange(
                velocity: (charge.attributes[.maxVelocity] ?? 0) * velocityMultiplier,
                flightTime: (charge.attributes[.explosionDelay] ?? 0) * flightTimeMultiplier / 1000,
                mass: charge.attributes[.mass] ?? 0,
                agility: charge.attributes[.agility] ?? 0)
        }

        // MARK: - Weapons

        /// Damage output of a channel, or `nil` if the type does not have it. `volley` is
        /// zero while the channel does not work; `cycleTime` is zero for `.kamikaze`.
        public func weapon(_ channel: Channel) -> Weapon? {
            let volley = rawVolleyDamage(of: channel)
            guard volley != .zero else { return nil }
            return weapon(channel, volley: isEnabled(channel) ? volley : .zero)
        }

        private func weapon(_ channel: Channel, volley: DamageVector) -> Weapon {
            let cycleTime = channel.isSustained ? cycleTime(of: channel) : 0
            switch channel {
            case .drone:
                // Drones with a built-in charge are missiles, the rest are turrets.
                guard let charge else {
                    return Weapon(application: .turret,
                                  volley: volley,
                                  cycleTime: cycleTime,
                                  optimal: optimal(of: channel),
                                  falloff: falloff(of: channel),
                                  accuracyScore: accuracyScore(of: channel),
                                  signatureResolution: signatureResolution(of: channel))
                }
                let velocityMultiplier = attributes[.missileEntityVelocityMultiplier, default: .sde]
                // `aoeDamageReductionFactor` on the charge is already the exponent.
                return Weapon(application: .missile,
                              volley: volley,
                              cycleTime: cycleTime,
                              optimal: optimal(of: channel),
                              explosionRadius: charge.attributes[.aoeCloudSize, default: .sde],
                              explosionVelocity: charge.attributes[.aoeVelocity, default: .sde],
                              damageReductionExponent: charge.attributes[.aoeDamageReductionFactor] ?? 0,
                              missileVelocity: (charge.attributes[.maxVelocity] ?? 0) * velocityMultiplier)

            case .fighterAttackTurret:
                return Weapon(application: .turret,
                              volley: volley,
                              cycleTime: cycleTime,
                              optimal: optimal(of: channel),
                              falloff: falloff(of: channel),
                              accuracyScore: accuracyScore(of: channel),
                              signatureResolution: signatureResolution(of: channel))

            case .fighterAttackMissile:
                // The exponent is precomputed by the importer from factor/sensitivity.
                return Weapon(application: .fighterMissile,
                              volley: volley,
                              cycleTime: cycleTime,
                              optimal: optimal(of: channel),
                              falloff: falloff(of: channel),
                              explosionRadius: attributes[.fighterAbilityAttackMissileExplosionRadius] ?? 0,
                              explosionVelocity: attributes[.fighterAbilityAttackMissileExplosionVelocity] ?? 0,
                              damageReductionExponent: attributes[.fighterAbilityAttackMissileReductionExponent] ?? 0)

            case .fighterMissiles:
                return Weapon(application: .fighterMissile,
                              volley: volley,
                              cycleTime: cycleTime,
                              optimal: optimal(of: channel),
                              falloff: falloff(of: channel),
                              explosionRadius: attributes[.fighterAbilityMissilesExplosionRadius] ?? 0,
                              explosionVelocity: attributes[.fighterAbilityMissilesExplosionVelocity] ?? 0,
                              damageReductionExponent: attributes[.fighterAbilityMissilesDamageReductionExponent] ?? 0)

            case .kamikaze:
                // Range gate only: detonation does not depend on target velocity.
                return Weapon(application: .rangeGate,
                              volley: volley,
                              cycleTime: cycleTime,
                              optimal: optimal(of: channel))
            }
        }

        /// Damage output of every channel the type has, see `weapon(_:)`.
        public var weapons: [Channel: Weapon] {
            var weapons: [Channel: Weapon] = [:]
            forEachWeapon { weapons[$0] = $1 }
            return weapons
        }

        /// Iterates the channels the type has, with their damage output.
        public func forEachWeapon(_ body: (Channel, Weapon) -> Void) {
            for channel in Channel.allCases {
                if let weapon = weapon(channel) {
                    body(channel, weapon)
                }
            }
        }

        // MARK: - DPS

        /// Fraction of a channel's damage that reaches the target. `target == .zero` means
        /// no target, multiplier 1.
        public func relativeDPS(of channel: Channel, to target: Target) -> Double {
            weapon(channel, volley: .zero).relativeDPS(to: target)
        }

        /// Channel volley adjusted for the target. For `.kamikaze` this is the whole detonation.
        public func volleyDamage(of channel: Channel, to target: Target) -> DamageVector {
            weapon(channel)?.volleyDamage(to: target) ?? .zero
        }

        /// Total volley over all working channels, adjusted for the target.
        public func volleyDamage(to target: Target) -> DamageVector {
            var result = DamageVector.zero
            forEachWeapon { result += $1.volleyDamage(to: target) }
            return result
        }

        /// DPS of one channel against the target, including `count`, state and kamikaze mode.
        /// Zero for `.kamikaze`; use `volleyDamage(of:to:)`.
        public func dps(of channel: Channel, to target: Target) -> DamageVector {
            weapon(channel)?.dps(to: target) ?? .zero
        }

        /// Total DPS of the drone/squadron against the target, summed over channels.
        /// `target == .zero` gives raw DPS. Zero in kamikaze mode.
        public func dps(to target: Target) -> DamageVector {
            var result = DamageVector.zero
            forEachWeapon { result += $1.dps(to: target) }
            return result
        }

        /// Raw DPS with no tracking or range adjustment.
        public func dps() -> DamageVector {
            dps(to: .zero)
        }

        @SnapshotField
        public func miningYield() -> Double {
            guard isOperating else { return 0 }
            let cycle = cycleTime()
            guard cycle > 0 else { return 0 }
            // Same as `Module.miningYield`; no SDE drone carries crit attributes today.
            let amount = attributes[.miningAmount] ?? 0
            let critBonus = (attributes[.miningCritChance] ?? 0) * (attributes[.miningCritBonusYield] ?? 0)
            return amount * (1 + critBonus) / cycle * Double(count)
        }

        /// Change of the target's capacitor per cycle for the whole stack if the drone is a
        /// neutralizer (`entityEnergyNeutralizerFalloff`).
        public func projectedCapacitorDelta() -> (drain: Double, recharge: Double) {
            guard isOperating else { return (0, 0) }
            let sde = session.pointee.sde
            guard sde[entity.info].effects.contains(where: {$0.id.load() == .entityEnergyNeutralizerFalloff}) else {return (0, 0)}
            let amount = (attributes[.energyNeutralizerAmount] ?? 0) * Double(count)
            return (amount, 0)
        }

        /// Simulator node for the target's capacitor.
        /// `disallowOffensive` / `disallowAssistance` block drain and injection respectively.
        public func projectedCapacitorNode(disallowOffensive: Bool,
                                           disallowAssistance: Bool) -> CapacitorSimulator.Node? {
            var delta = projectedCapacitorDelta()
            if disallowOffensive {
                delta.drain = 0
            }
            if disallowAssistance {
                delta.recharge = 0
            }
            
            let amount = delta.recharge - delta.drain
            guard amount != 0 else { return nil }
            
            let cycle = rawCycleTime
            guard cycle > 0 else { return nil }

            return CapacitorSimulator.Node(cycleTime: cycle, drain: delta.drain, recharge: delta.recharge, clipSize: 0, reloadTime: 0)
        }
    }
}
