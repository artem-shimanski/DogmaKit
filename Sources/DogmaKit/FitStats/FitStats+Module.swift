//
//  FitStats+Module.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 06.07.2026.
//

import Foundation

extension FitStats {
    public struct Module: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: ModuleID
        @inlinable var entityID: EntityID {id.rawValue}
        public let attributes: EntityAttributes
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: ModuleID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }

        @inlinable
        var entity: Entity {
            session.pointee.entities[entityID]!
        }

        public var typeID: TypeID {
            entity.typeID
        }

        /// Whether the module can have a target (see `Fit.Module.isProjectable`).
        public var isProjectable: Bool {
            let sde = session.pointee.sde
            return Entity.Module.isProjectable(sde[entity.info])
        }

        public var slot: Entity.Module.Slot {
            entity.kind.module!.slot
        }
        
        public var hardpoint: Entity.Module.Hardpoint {
            entity.kind.module!.hardpoint
        }

        /// Position of the module in its rack. Can exceed `Hull.capacity(of:)` when the
        /// hull is overfitted.
        public var socket: Int {
            Int(entity.kind.module!.socket)
        }

        /// Rig size; `.none` if the module is not a rig.
        public var rigSize: RigSize {
            RigSize(attributes[.rigSize] ?? 0)
        }

        /// Subsystem slot, if the module is a T3C subsystem.
        public var subsystemSlot: Entity.Module.SubsystemSlot? {
            guard let value = attributes[.subSystemSlot] else { return nil }
            return UInt8(exactly: value.rounded()).flatMap(Entity.Module.SubsystemSlot.init(rawValue:))
        }

        /// What the module can do (online, activate, overload, require a target, force reload).
        public var flags: Entity.Module.Flags {
            entity.kind.module!.flags
        }

        /// The highest state the module supports.
        public var maxAllowedState: Entity.Module.State {
            flags.maxAllowedState
        }

        /// State requested by the user.
        public var state: Entity.Module.State {
            entity.kind.module!.state
        }

        /// State allowed by the engine. Lower than `state` when the module was demoted
        /// (`maxGroupActive`/`maxGroupOnline` exceeded, activation blocked, etc.).
        public var effectiveState: Entity.Module.State {
            session.pointee.context[effectiveState: entityID]
        }
        
        public var cpuUse: Double {
            attributes[.cpu] ?? 0
        }
        
        public var powerGridUse: Double {
            attributes[.power] ?? 0
        }
        
        public var calibrationUse: Double {
            attributes[.upgradeCost] ?? 0
        }

        /// Fuel blocks per hour this service module burns while online, regardless of its state.
        public var serviceFuelPerHour: Double {
            attributes[.serviceModuleFuelAmount] ?? 0
        }

        /// Fuel blocks spent once to bring this service module online.
        public var serviceFuelToOnline: Double {
            attributes[.serviceModuleFuelOnlineAmount] ?? 0
        }
        
        public var charge: Charge? {
            @_lifetime(borrow self)
            get {
                let chargeID = id.charge
                guard session.pointee.entities.contains(chargeID.rawValue) else {return nil}
                return Charge(session: session, id: chargeID)
            }
        }
        
        public var chargeSize: Entity.Charge.Size? {
            guard let value = attributes[.chargeSize] else {return nil}
            return Entity.Charge.Size(rawValue: UInt8(value))
        }
        
        public var chargeGroup: [GroupID]? {
            let sde = session.pointee.sde
            let entity = self.entity
            // Abyssal modules keep the charge group list on the base type.
            if let requirements = sde[entity.info].chargeRequirements {
                return requirements.chargeGroup.load()
            }
            if let mutation = entity.mutation,
               let requirements = sde[mutation.baseType].chargeRequirements {
                return requirements.chargeGroup.load()
            }
            return nil
        }

        /// Whether the module is mutated (abyssal). All other stats already use the mutated values.
        public var isMutated: Bool {
            entity.mutation != nil
        }

        /// Type ID of the mutaplasmid applied to the module.
        public var mutaplasmidTypeID: TypeID? {
            session.pointee.mutaplasmidTypeID(of: entityID)
        }

        /// Type ID of the base (unmutated) type.
        public var baseTypeID: TypeID? {
            session.pointee.baseTypeID(of: entityID)
        }

        /// Iterates the module's rolls. Mutaplasmid attributes without a roll report the
        /// base value (multiplier 1.0).
        public func forEachRoll(_ body: (MutationRoll) -> Void) {
            session.pointee.forEachRoll(of: entityID, body)
        }
        
        public var reloadTime: Double {
            if let reloadTime = attributes[.reloadTime] {
                return reloadTime / 1000
            }
            else {
                return entity.kind.module!.defaultReloadTime
            }
        }
        
        public var rawCycleTime: Double {
            Global.cycleTimeAttributes.reduce(0.0) {max($0, attributes[$1] ?? 0)} / 1000
        }
        
        /// Cycle time, seconds, using the current read's reload policy.
        public func cycleTime() -> Double {
            cycleTime(reload: session.pointee.reload)
        }

        func cycleTime(reload: ReloadPolicy) -> Double {
            let clipSize = clipSize(reload: reload)
            if clipSize > 0 {
                let cycles = Double(clipSize)
                let reactivation = attributes[.moduleReactivationDelay, default: .sde] / 1000
                return (rawCycleTime * cycles + max(reloadTime, reactivation)) / cycles
            }
            return rawCycleTime
        }
        
        /// Spool-up under the current read's spool policy. `nil` if the module does not spool.
        public func spool(_ kind: SpoolKind) -> Spool? {
            spool(kind, policy: session.pointee.spool)
        }

        /// Spool-up of either kind: damage first, then repair (no SDE type has both).
        public var spool: Spool? {
            spool(.damage) ?? spool(.repair)
        }

        func spool(_ kind: SpoolKind, policy: SpoolPolicy) -> Spool? {
            Spool(max: attributes[kind.maxAttributeID] ?? 0,
                  perCycle: attributes[kind.perCycleAttributeID] ?? 0,
                  cycleTime: rawCycleTime,
                  policy: policy)
        }

        /// Spool multiplier, `1` if the module does not spool.
        func spoolMultiplier(_ kind: SpoolKind) -> Double {
            spool(kind)?.multiplier ?? 1
        }

        /// What the module repairs.
        public enum RepairKind: Sendable {
            case shield, armor, hull
        }

        /// A module's repair rate.
        public struct Repair: Sendable {
            /// Repaired layer.
            public var kind: RepairKind
            /// `true` for remote reps (repairs the target, not the own hull).
            public var isRemote: Bool
            /// Repair, HP/s.
            public var hpPerSecond: Double
        }

        /// Repair rate of this module, or `nil` if it is not active or not a repairer.
        /// The per-cycle amount is divided by `cycleTime()`, so ancillary repairers spread
        /// the reload over the cycle, while `.ignored` gives the peak rate. Mutadaptive
        /// repairers are multiplied by `spool(.repair)`.
        public func repair() -> Repair? {
            repair(reload: session.pointee.reload)
        }

        func repair(reload: ReloadPolicy) -> Repair? {
            guard effectiveState >= .active else { return nil }
            let sde = session.pointee.sde
            var kind: RepairKind?
            var isRemote = false
            sde[entity.info].effects.forEach { effect in
                switch effect.id.load() {
                case .shieldBoosting, .fueledShieldBoosting:
                    kind = .shield
                case .armorRepair, .fueledArmorRepair:
                    kind = .armor
                case .structureRepair:
                    kind = .hull
                case .shipModuleRemoteShieldBooster, .shipModuleAncillaryRemoteShieldBooster:
                    kind = .shield
                    isRemote = true
                case .shipModuleRemoteArmorRepairer, .shipModuleAncillaryRemoteArmorRepairer,
                     .shipModuleRemoteArmorMutadaptiveRepairer:
                    kind = .armor
                    isRemote = true
                case .shipModuleRemoteHullRepairer:
                    kind = .hull
                    isRemote = true
                default:
                    break
                }
            }
            guard let kind else { return nil }
            let amount: Double
            switch kind {
            case .shield: amount = attributes[.shieldBonus] ?? 0
            case .armor: amount = attributes[.armorDamageAmount] ?? 0
            case .hull: amount = attributes[.structureDamageAmount] ?? 0
            }
            guard amount != 0 else { return nil }
            let cycle = cycleTime(reload: reload)
            guard cycle > 0 else { return nil }
            return Repair(kind: kind, isRemote: isRemote,
                          hpPerSecond: abs(amount) * spoolMultiplier(.repair) / cycle)
        }

        /// Capacitor use, GJ/s. Uses `ReloadPolicy.forCapacitor`.
        public func capUse() -> Double {
            capUse(reload: session.pointee.reload.forCapacitor)
        }

        func capUse(reload: ReloadPolicy) -> Double {
            guard effectiveState >= .active else {return 0}
            let cycle = cycleTime(reload: reload)
            guard cycle > 0 else {return 0}

            let delta = capacitorDelta()

            let capNeed = delta.drain - delta.recharge

            return capNeed / cycle
        }

        /// Change of the own capacitor per activation, GJ: `drain` is consumption,
        /// `recharge` is injection (cap boosters, nosferatu).
        func capacitorDelta() -> (drain: Double, recharge: Double) {
            guard effectiveState >= .active else { return (0, 0) }
            let sde = session.pointee.sde
            var drain = 0.0
            var recharge = 0.0
            if let value = attributes[.capacitorNeed], value != 0 {
                drain += value
            }
            if let value = attributes[.powerTransferAmount], value != 0,
               sde[entity.info].effects.contains(where: { $0.id.load() == .energyNosferatuFalloff }) {
                recharge += value
            }
            if let value = charge?.attributes[.capacitorBonus], value != 0,
                    sde[entity.info].effects.contains(where: { $0.id.load() == .powerBooster }) {
                recharge += value
            }
            return (drain, recharge)
        }

        /// Change of the target's capacitor per activation when projected: neutralizers and
        /// nosferatu drain, remote capacitor transmitters recharge.
        func projectedCapacitorDelta() -> (drain: Double, recharge: Double) {
            guard effectiveState >= .active else { return (0, 0) }
            let sde = session.pointee.sde
            var drain = 0.0
            var recharge = 0.0
            sde[entity.info].effects.forEach { effect in
                switch effect.id.load() {
                case .energyNosferatuFalloff:
                    drain += (attributes[.powerTransferAmount] ?? 0)
                case .energyNeutralizerFalloff:
                    drain += (attributes[.energyNeutralizerAmount] ?? 0)
                case .shipModuleRemoteCapacitorTransmitter:
                    recharge += attributes[.powerTransferAmount] ?? 0
                default:
                    break
                }
            }
            return (drain, recharge)
        }

        /// Activations before a reload (clip size). `0` means reload is not part of the cycle.
        func clipSize(reload: ReloadPolicy) -> Int {
            guard reload.countsClip(forced: entity.kind.module!.flags.forceReload),
                  let charge
            else { return 0 }
            let chargeVolume = charge.attributes[.volume] ?? 0
            let capacity = attributes[.capacity] ?? 0
            let charges = chargeVolume > 0 ? (capacity / chargeVolume).rounded(.down) : 0
            guard charges > 0 else { return 0 }
            let cycles: Double
            if let chargeRate = attributes[.chargeRate], chargeRate > 0 {
                cycles = charges / chargeRate
            }
            else if let crystalsGetDamaged = attributes[.crystalsGetDamaged], crystalsGetDamaged > 0 {
                let hp = charge.attributes[.hp] ?? 0
                let chance = charge.attributes[.crystalVolatilityChance, default: .sde]
                let damage = charge.attributes[.crystalVolatilityDamage, default: .sde]
                let fullDamage = damage * chance
                cycles = fullDamage > 0 ? charges * hp / fullDamage : 0
            }
            else { cycles = 0 }
            return Int(cycles.rounded(.down))
        }

        /// Simulator node for a given per-activation capacitor change. Within a clip
        /// activations are `rawCycleTime` apart; between clips there is a discrete gap of
        /// `max(reloadTime, reactivationDelay)`. Without a clip, reactivation is added to every cycle.
        func capacitorNode(drain: Double, recharge: Double, reload: ReloadPolicy) -> CapacitorSimulator.Node? {
            let amount = recharge - drain
            guard amount != 0 else { return nil }
            let raw = rawCycleTime
            guard raw > 0 else { return nil }
            let reactivation = attributes[.moduleReactivationDelay, default: .sde] / 1000
            let clip = clipSize(reload: reload)
            if clip > 0 {
                return CapacitorSimulator.Node(cycleTime: raw,
                                               drain: drain,
                                               recharge: recharge,
                                               clipSize: clip,
                                               reloadTime: max(reloadTime, reactivation))
            }
            else {
                return CapacitorSimulator.Node(cycleTime: raw + reactivation,
                                               drain: drain,
                                               recharge: recharge,
                                               clipSize: 0, reloadTime: 0)
            }
        }

        /// Heat simulator node, or `nil` if the module is not overloaded.
        ///
        /// Gated on `effectiveState`: a module demoted by the engine does not heat the rack.
        /// The reload policy is not applied: heat runs in real time, so the clip is always
        /// counted and the reload pause is inserted discretely.
        public func heatNode() -> HeatSimulator.Node? {
            guard effectiveState == .overloaded else { return nil }
            let raw = rawCycleTime
            guard raw > 0 else { return nil }

            let damage = attributes[.heatDamage] ?? 0
            let absorbtion = attributes[.heatAbsorbtionRateModifier, default: .sde]
            let reactivation = attributes[.moduleReactivationDelay, default: .sde] / 1000
            let clip = clipSize(reload: .factored)

            if clip > 0 {
                return HeatSimulator.Node(socket: socket,
                                          cycleTime: raw,
                                          clipSize: clip,
                                          reloadTime: max(reloadTime, reactivation),
                                          absorbtionRate: absorbtion,
                                          damage: damage)
            }
            else {
                return HeatSimulator.Node(socket: socket,
                                          cycleTime: raw + reactivation,
                                          clipSize: 0,
                                          reloadTime: 0,
                                          absorbtionRate: absorbtion,
                                          damage: damage)
            }
        }

        /// Simulator node for the own capacitor, or `nil` if the module does not affect it.
        public func capacitorNode() -> CapacitorSimulator.Node? {
            let delta = capacitorDelta()
            return capacitorNode(drain: delta.drain,
                                 recharge: delta.recharge,
                                 reload: session.pointee.reload.forCapacitor)
        }

        /// Simulator node for the target's capacitor (incoming neut/nos/remote cap).
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
            return capacitorNode(drain: delta.drain,
                                 recharge: delta.recharge,
                                 reload: session.pointee.reload.forCapacitor)
        }
        
        public var volleyDamage: DamageVector {
            guard effectiveState >= .active else {return .zero}
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
            let spoolFactor = spoolMultiplier(.damage)
            return (multiplier > 0 ? volley * multiplier : volley) * spoolFactor
        }
        
        func turretRelativeDPS(to target: Target) -> Double {
            WeaponMath.turretRelativeDPS(accuracyScore: accuracyScore,
                                        signatureResolution: signatureResolution,
                                        optimal: optimal,
                                        falloff: falloff,
                                        to: target)
        }

        func missileRelativeDPS(to target: Target) -> Double {
            guard let charge, optimal >= target.range else {return 0}

            if target.velocity > 0 {
                let missileEntityVelocityMultiplier = attributes[.missileEntityVelocityMultiplier, default: .sde]
                let maxVelocity = (charge.attributes[.maxVelocity] ?? 0) * missileEntityVelocityMultiplier
                if maxVelocity < target.velocity {
                    return 0
                }
            }

            // `aoeDamageReductionFactor` on the charge is already the exponent;
            // `aoeDamageReductionSensitivity` is not set on any SDE type.
            return WeaponMath.missileDamageFactor(
                explosionRadius: charge.attributes[.aoeCloudSize, default: .sde],
                explosionVelocity: charge.attributes[.aoeVelocity, default: .sde],
                damageReductionExponent: charge.attributes[.aoeDamageReductionFactor] ?? 0,
                to: target)
        }
        
        /// Fraction of damage that reaches the target: tracking and range for turrets,
        /// explosion radius/velocity and flight range for missiles, a hard range gate for
        /// everything else. `target == .zero` means no target, multiplier 1.
        public func relativeDPS(to target: Target) -> Double {
            guard target != .zero else {return 1}

            switch hardpoint {
            case .none:
                return optimal >= target.range ? 1 : 0
            case .launcher:
                return missileRelativeDPS(to: target)
            case .turret:
                return turretRelativeDPS(to: target)
            }
        }

        /// Volley adjusted for the target.
        public func volleyDamage(to target: Target) -> DamageVector {
            let relative = relativeDPS(to: target)
            guard relative > 0 else {return .zero}
            return volleyDamage * relative
        }

        public func dps(to target: Target) -> DamageVector {
            let cycle = cycleTime()
            guard cycle > 0 else {return .zero}
            let relative = relativeDPS(to: target)
            guard relative > 0 else {return .zero}
            return volleyDamage / cycle * relative
        }
        
        public var optimal: Double {
            for attributeID in Global.optimalAttributes {
                if let value = attributes[attributeID], value > 0 {
                    return value
                }
            }
            guard let charge else { return 0 }
            return missileFlightRange(charge: charge)
        }

        /// Missile flight range for this launcher, including its velocity and flight time multipliers.
        func missileFlightRange(charge: borrowing Charge) -> Double {
            let missileEntityVelocityMultiplier = attributes[.missileEntityVelocityMultiplier, default: .sde]
            let missileEntityFlightTimeMultiplier = attributes[.missileEntityFlightTimeMultiplier, default: .sde]

            return WeaponMath.missileFlightRange(
                velocity: (charge.attributes[.maxVelocity] ?? 0) * missileEntityVelocityMultiplier,
                flightTime: (charge.attributes[.explosionDelay] ?? 0) * missileEntityFlightTimeMultiplier / 1000,
                mass: charge.attributes[.mass] ?? 0,
                agility: charge.attributes[.agility] ?? 0)
        }
        
        public var falloff: Double {
            for attributeID in Global.falloffAttributes {
                if let value = attributes[attributeID], value > 0 {
                    return value
                }
            }
            return 0
        }
        
        public var accuracyScore: Double {
            attributes[.trackingSpeed, default: .sde]
        }
        
        public var signatureResolution: Double {
            attributes[.optimalSigRadius, default: .sde]
        }
        
        /// Average yield, m³/s: `miningAmount` per cycle, including the expected critical
        /// bonus `miningCritChance · miningCritBonusYield`. `specialtyMiningAmount`
        /// is not added: the SDE only mirrors `miningAmount` into it for display.
        public func miningYield() -> Double {
            guard effectiveState >= .active else {return 0}
            let cycle = cycleTime()
            guard cycle > 0 else {return 0}
            let amount = attributes[.miningAmount] ?? 0
            let critBonus = (attributes[.miningCritChance] ?? 0) * (attributes[.miningCritBonusYield] ?? 0)
            return amount * (1 + critBonus) / cycle
        }
        
        /// Propulsion parameters (afterburner / microwarpdrive), or `nil` if not a propulsion module.
        /// Values already include skill, rig and tactical destroyer mode bonuses.
        public var propulsion: Propulsion? {
            let sde = session.pointee.sde
            var isPropulsion = false
            sde[entity.info].effects.forEach { effect in
                switch effect.id.load() {
                case .moduleBonusAfterburner, .moduleBonusMicrowarpdrive: isPropulsion = true
                default: break
                }
            }
            guard isPropulsion else { return nil }
            // 1/100 is the default of the synthetic `speedBoostFactorCalc`.
            let thrust = (attributes[.speedFactor] ?? 0) * (attributes[.speedBoostFactor] ?? 0) / 100
            return Propulsion(thrust: thrust,
                              massAddition: attributes[.massAddition] ?? 0,
                              signatureRadiusBonus: attributes[.signatureRadiusBonus] ?? 0)
        }

        /// ECM parameters, or `nil` if the module is not a jammer. State is not checked;
        /// `Hull.forEachECM` gates on `effectiveState`.
        public var ecm: ECM? {
            let sde = session.pointee.sde
            var isECM = false
            sde[entity.info].effects.forEach { effect in
                if effect.id.load() == .remoteECMFalloff { isECM = true }
            }
            guard isECM else { return nil }
            var strength = SensorStrength()
            for type in SensorType.allCases {
                strength[type] = attributes[type.jamStrengthAttributeID] ?? 0
            }
            return ECM(strength: strength,
                       optimal: optimal,
                       falloff: falloff,
                       // Jammers use no ammo, so the reload policy does not apply.
                       cycleTime: cycleTime(reload: .ignored))
        }

        /// Probe scan strength bonus of this module (probe launchers). The resulting probe
        /// strength lives on the pilot (`FitStats.Pilot.probeScanStrength`).
        public var probeScanStrengthBonus: Double? {
            attributes[.scanStrengthBonus]
        }

        public func maxAngularVelocity(for targetSignature: Double, atHitChance hitChance: Double) -> Double {
            guard hitChance > 0 && hitChance <= 1.0 else { return 0.0 }
            
            let sigResolution = self.signatureResolution
            let accScore = self.accuracyScore
            
            guard sigResolution > 0 && accScore > 0 else { return 0.0 }
            
            // log(0.5)
            let logHalf: Double = -0.69314718056
            let multiplier = sqrt(log(hitChance) / logHalf)
            
            return (multiplier * accScore * targetSignature) / sigResolution
        }
    }
}

