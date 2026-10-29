//
//  FitStats+Hull.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 05.07.2026.
//

extension Entity.Module.Hardpoint {
    /// The damage source category for a module with this hardpoint.
    var damageSource: FitStats.Hull.DamageSource {
        switch self {
        case .none: .otherModules
        case .launcher: .launchers
        case .turret: .turrets
        }
    }
}

extension FitStats {

    @Snapshottable
    public struct Hull: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: HullID
        @inlinable var entityID: EntityID {id.rawValue}
        
        @SnapshotIgnored public let attributes: EntityAttributes
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: HullID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }
        
        @inlinable
        var entity: Entity {
            session.pointee.entities[entityID]!
        }

        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }

        @SnapshotNested
        public var modules: Modules {
            @_lifetime(borrow self) get {
                Modules(hull: self)
            }
        }

        @SnapshotNested
        public var drones: Drones {
            @_lifetime(borrow self) get {
                Drones(hull: self)
            }
        }

        // MARK: - Damage

        /// Damage source categories of a hull. Used as a mask in `dps(from:to:)` /
        /// `volleyDamage(from:to:)`: only the listed categories are summed.
        public struct DamageSource: OptionSet, Sendable, Hashable {
            public let rawValue: UInt8

            @inlinable
            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }

            /// Modules with a turret hardpoint.
            public static let turrets = DamageSource(rawValue: 1 << 0)
            /// Modules with a launcher hardpoint (missiles, torpedoes, bombs).
            public static let launchers = DamageSource(rawValue: 1 << 1)
            /// Other damaging modules without a hardpoint (smartbombs, etc.).
            public static let otherModules = DamageSource(rawValue: 1 << 2)
            /// Regular drones (`Entity.Drone.Squadron.none`).
            public static let drones = DamageSource(rawValue: 1 << 3)
            /// Fighters (any squadron, including structure variants).
            public static let fighters = DamageSource(rawValue: 1 << 4)

            /// All module sources.
            public static let modules: DamageSource = [.turrets, .launchers, .otherModules]
            /// All deployable sources (drones and fighters).
            public static let deployables: DamageSource = [.drones, .fighters]
            /// All of the hull's weaponry.
            public static let all: DamageSource = [.modules, .drones, .fighters]
        }

        private static let damageSlots: [Entity.Module.Slot] = [.hi, .med, .low]

        /// Damaging modules in hi/med/low racks and every channel of the hull's drones and
        /// fighters. Modules fire only when `effectiveState >= .active`, drones only when
        /// `isActive`; others are listed with a zero volley.
        public var armament: Armament {
            var entries: [Armament.Entry] = []
            for slot in Self.damageSlots {
                modules.forEach(in: slot) { module in
                    guard let weapon = module.weapon else { return }
                    entries.append(.init(source: module.hardpoint.damageSource,
                                         entityID: module.id.rawValue,
                                         weapon: weapon))
                }
            }
            drones.forEach { drone in
                let source: DamageSource = drone.squadron == .none ? .drones : .fighters
                let entityID = drone.id.rawValue
                drone.forEachWeapon { channel, weapon in
                    entries.append(.init(source: source, entityID: entityID, channel: channel, weapon: weapon))
                }
            }
            return Armament(entries: entries)
        }

        /// Total DPS of the hull from the given source categories.
        /// `target == .zero` gives raw DPS with no tracking, range or missile flight penalties.
        /// Modules count only when `effectiveState >= .active`, drones only when `isActive`.
        public func dps(from sources: DamageSource = .all,
                        to target: Target = .zero) -> DamageVector {
            armament.dps(from: sources, to: target)
        }

        /// Total volley (alpha strike) of the hull from the given source categories:
        /// damage of one cycle of every weapon fired at once.
        public func volleyDamage(from sources: DamageSource = .all,
                                 to target: Target = .zero) -> DamageVector {
            armament.volleyDamage(from: sources, to: target)
        }

        public var cpu: Resource {
            Resource(used: attributes[.cpuLoad] ?? 0, total: attributes[.cpuOutput] ?? 0)
        }

        public var powerGrid: Resource {
            Resource(used: attributes[.powerLoad] ?? 0, total: attributes[.powerOutput] ?? 0)
        }
        
        public var calibration: Resource {
            let total = attributes[.upgradeCapacity] ?? 0
            var sum: Double = 0
            modules.forEach(in: .rig) { sum += $0.calibrationUse }
            return Resource(used: sum, total: total)
        }
        
        /// Fuel blocks per hour burned by the structure's online service modules.
        public var fuelPerHour: Double {
            var sum: Double = 0
            modules.forEach(in: .service) { module in
                guard module.effectiveState >= .online else { return }
                sum += module.serviceFuelPerHour
            }
            return sum
        }

        /// Fuel blocks spent once to online the structure's currently online service modules.
        public var fuelToOnline: Double {
            var sum: Double = 0
            modules.forEach(in: .service) { module in
                guard module.effectiveState >= .online else { return }
                sum += module.serviceFuelToOnline
            }
            return sum
        }

        /// Drone bay: `used` is the volume of all drone stacks (drones in space still occupy
        /// bay space), `total` is the hull's `droneCapacity`. Fighters go to `fighterBay`.
        public var droneBay: Resource {
            var used: Double = 0
            drones.forEach { drone in
                guard drone.squadron == .none else { return }
                used += drone.volume * Double(drone.count)
            }
            return Resource(used: used, total: attributes[.droneCapacity] ?? 0)
        }

        /// Fighter bay: `used` is the volume of all squadrons (launched ones included), `total`
        /// is the hull's `fighterCapacity`.
        public var fighterBay: Resource {
            var used: Double = 0
            drones.forEach { drone in
                guard drone.squadron != .none else { return }
                used += drone.volume * Double(drone.count)
            }
            return Resource(used: used, total: attributes[.fighterCapacity] ?? 0)
        }

        /// Drone bandwidth: only drones in space use it, so `used` counts active stacks only.
        public var droneBandwidth: Resource {
            var used: Double = 0
            drones.forEach { drone in
                guard drone.isActive else { return }
                used += drone.bandwidthUsed * Double(drone.count)
            }
            return Resource(used: used, total: attributes[.droneBandwidth] ?? 0)
        }

        /// Drones in space: active ordinary drones, fighters excluded (launched squadrons are
        /// `fighterTubes.used`). `total` is the pilot's `maxActiveDrones` (a pilot attribute,
        /// not a hull one).
        public var dronesInSpace: SlotCapacity {
            var used = 0
            drones.forEach(in: .none) { drone in
                guard drone.isActive else { return }
                used += drone.count
            }
            let pilot = Pilot(session: session, id: id.pilot)
            return SlotCapacity(used: used, total: Int(pilot.attributes[.maxActiveDrones] ?? 0))
        }

        /// Fighter launch tubes: `used` is the number of launched squadrons, `total` is the
        /// hull's `fighterTubes`.
        public var fighterTubes: SlotCapacity {
            var used = 0
            drones.forEach { drone in
                guard drone.squadron != .none, drone.isActive else { return }
                used += 1
            }
            return SlotCapacity(used: used, total: Int(attributes[.fighterTubes] ?? 0))
        }

        /// Squadron slots of one fighter type: `used` is the number of squadrons of that type
        /// in the fit, launched or not; `total` is the hull's slot count for it. `total` is
        /// `0` for `.none`.
        public func capacity(of squadron: Entity.Drone.Squadron) -> SlotCapacity {
            let total = squadron.slotsAttributeID.map { Int(attributes[$0] ?? 0) } ?? 0
            return SlotCapacity(used: drones.count(in: squadron), total: total)
        }

        /// `capacity(of:)` for every fighter squadron type.
        public var squadrons: [Entity.Drone.Squadron: SlotCapacity] {
            var squadrons: [Entity.Drone.Squadron: SlotCapacity] = [:]
            for squadron in Entity.Drone.Squadron.allCases where squadron != .none {
                squadrons[squadron] = capacity(of: squadron)
            }
            return squadrons
        }

        /// Cargo hold, m³ (`capacity`).
        public var cargoCapacity: Double {
            attributes[.capacity] ?? 0
        }

        /// Rig size accepted by the hull. `.none` means the hull takes no rigs (shuttles, capsules).
        public var rigSize: RigSize {
            RigSize(attributes[.rigSize] ?? 0)
        }

        public func capacity(of slot: Entity.Module.Slot) -> SlotCapacity {
            let total = Int(attributes[slot.attributeID] ?? 0)
            let used = modules.count(in: slot)
            return SlotCapacity(used: used, total: total)
        }

        /// `capacity(of:)` for every slot.
        public var slots: [Entity.Module.Slot: SlotCapacity] {
            var slots: [Entity.Module.Slot: SlotCapacity] = [:]
            for slot in Entity.Module.Slot.allCases {
                slots[slot] = capacity(of: slot)
            }
            return slots
        }

        public var turretHardpoints: SlotCapacity {
            capacity(of: .turret)
        }

        public var launcherHardpoints: SlotCapacity {
            capacity(of: .launcher)
        }

        public func capacity(of hardpoint: Entity.Module.Hardpoint) -> SlotCapacity {
            var used = 0
            modules.forEach(in: .hi) { module in
                if module.hardpoint == hardpoint {
                    used += 1
                }
            }
            switch hardpoint {
            case .launcher:
                let free = Int(attributes[.launcherSlotsLeft] ?? 0)
                return SlotCapacity(used: used, total: free + used)
            case .turret:
                let free = Int(attributes[.turretSlotsLeft] ?? 0)
                return SlotCapacity(used: used, total: free + used)
            case .none:
                return SlotCapacity(used: used, total: -1)
            }
        }

        // MARK: - Navigation

        private static let activeModuleSlots: [Entity.Module.Slot] = [.hi, .med, .low]

        /// Navigation as computed: `maxVelocity`, `mass` and `signatureRadius` already
        /// include the contribution of active propulsion modules.
        public var navigation: Navigation {
            Navigation(maxVelocity: attributes[.maxVelocity] ?? 0,
                       mass: attributes[.mass] ?? 0,
                       agility: attributes[.agility] ?? 0,
                       signatureRadius: attributes[.signatureRadius] ?? 0,
                       warpSpeed: attributes[.baseWarpSpeed, default: .sde]
                                * attributes[.warpSpeedMultiplier, default: .sde],
                       warpCapacitorNeed: attributes[.warpCapacitorNeed] ?? 0,
                       capacitorCapacity: attributes[.capacitorCapacity] ?? 0)
        }

        /// Navigation without active propulsion modules. See `Navigation.removing(_:)`
        /// for the precision caveat.
        public var unboostedNavigation: Navigation {
            var result = navigation
            for slot in Self.activeModuleSlots {
                modules.forEach(in: slot) { module in
                    guard module.effectiveState >= .active,
                          let propulsion = module.propulsion
                    else { return }
                    result = result.removing(propulsion)
                }
            }
            return result
        }

        /// Navigation with only `propulsionModule` active and all other propulsion
        /// modules off. Returns `unboostedNavigation` if the module does not exist
        /// or is not a propulsion module.
        public func navigation(with propulsionModule: ModuleID) -> Navigation {
            let base = unboostedNavigation
            // Check existence first: `modules[_:]` force-unwraps the entity.
            guard let entity = session.pointee.entities[propulsionModule.rawValue],
                  entity.kind.module != nil,
                  let propulsion = modules[propulsionModule].propulsion
            else { return base }
            return base.applying(propulsion)
        }

        // MARK: - Targeting

        /// Targeting characteristics. Lock time is `Targeting.lockTime(signatureRadius:)`.
        public var targeting: Targeting {
            // The pilot's limit is a character attribute (domain charID in the SDE). Without a
            // pilot entry the ship's limit alone applies.
            let pilot = Pilot(session: session, id: id.pilot)
            let shipLimit = attributes[.maxLockedTargets] ?? 0
            let limit = pilot.attributes[.maxLockedTargets].map { min(shipLimit, $0) } ?? shipLimit
            return Targeting(maxTargetRange: attributes[.maxTargetRange] ?? 0,
                             scanResolution: attributes[.scanResolution] ?? 0,
                             maxLockedTargets: Int(limit),
                             sensorStrength: sensorStrength,
                             scanSpeed: attributes[.scanSpeed] ?? 0)
        }

        /// Sensor strength by type (also the ECM resistance). A ship has exactly one
        /// non-zero type (`SensorStrength.dominant`).
        public var sensorStrength: SensorStrength {
            var result = SensorStrength()
            for type in SensorType.allCases {
                result[type] = attributes[type.strengthAttributeID] ?? 0
            }
            return result
        }

        // MARK: - ECM

        /// Iterates the hull's active ECM modules.
        public func forEachECM(_ body: (ModuleID, ECM) -> Void) {
            for slot in Self.activeModuleSlots {
                modules.forEach(in: slot) { module in
                    guard module.effectiveState >= .active, let ecm = module.ecm else { return }
                    body(module.id, ecm)
                }
            }
        }

        /// Summed jam strength of active ECM modules by target sensor type. This is a
        /// summary figure only: each jammer rolls independently, so use
        /// `ECM.jamProbability(against:at:)` per module for the actual chance.
        public var ecmStrength: SensorStrength {
            var result = SensorStrength()
            forEachECM { _, ecm in result += ecm.strength }
            return result
        }

        public var hitPoints: HitPoints {
            let shield = attributes[.shieldCapacity] ?? 0
            let armor = attributes[.armorHP] ?? 0
            let hull = attributes[.hp] ?? 0
            return HitPoints(shield: shield, armor: armor, hull: hull)
        }
        
        public var resonance: Resonance {
            Resonance (
                shield: DamageVector(em: attributes[.shieldEmDamageResonance, default: .sde],
                                     thermal: attributes[.shieldThermalDamageResonance, default: .sde],
                                     kinetic: attributes[.shieldKineticDamageResonance, default: .sde],
                                     explosive: attributes[.shieldExplosiveDamageResonance, default: .sde]),
                armor: DamageVector(em: attributes[.armorEmDamageResonance, default: .sde],
                                    thermal: attributes[.armorThermalDamageResonance, default: .sde],
                                    kinetic: attributes[.armorKineticDamageResonance, default: .sde],
                                    explosive: attributes[.armorExplosiveDamageResonance, default: .sde]),
                hull: DamageVector(em: attributes[.emDamageResonance, default: .sde],
                                   thermal: attributes[.thermalDamageResonance, default: .sde],
                                   kinetic: attributes[.kineticDamageResonance, default: .sde],
                                   explosive: attributes[.explosiveDamageResonance, default: .sde])
            )
        }
        
        public var resistances: Resistances {
            resonance.resistances
        }
        
        /// Capacitor stability simulator built from the hull's active modules and incoming
        /// projected effects (neutralizers, nosferatu, remote capacitor transmitters).
        /// Uses `ReloadPolicy.forCapacitor`: ignoring reloads would give a cap booster
        /// infinite charge.
        @SnapshotField
        public func capacitorSimulator() -> CapacitorSimulator {
            let capacity = attributes[.capacitorCapacity] ?? 0
            let rechargeTime = (attributes[.rechargeRate, default: .sde]) / 1000
            var nodes: [CapacitorSimulator.Node] = []

            for slot in [Entity.Module.Slot.hi, .med, .low] {
                modules.forEach(in: slot) { module in
                    if let node = module.capacitorNode() {
                        nodes.append(node)
                    }
                }
            }

            appendProjectedNodes(into: &nodes)

            return CapacitorSimulator(capacity: capacity, rechargeTime: rechargeTime, nodes: nodes)
        }

        private func appendProjectedNodes(into nodes: inout [CapacitorSimulator.Node]) {
            let bit = UInt8(1) << entityID.pilotID
            let disallowOffensive = (session.pointee.context.disallowOffensiveMask & bit) != 0
            let disallowAssistance = (session.pointee.context.disallowAssistanceMask & bit) != 0
            let myPilot = id.pilot

            for otherHull in session.pointee.entities.hulls() where otherHull.pilot != myPilot.rawValue {
                for moduleID in session.pointee.entities.modules(on: otherHull) {
                    guard let target = session.pointee.entities[moduleID]?.kind.module?.target,
                          target != .invalid, target.hull == entityID else { continue }
                    let module = Module(session: session, id: ModuleID(rawValue: moduleID))
                    if let node = module.projectedCapacitorNode(disallowOffensive: disallowOffensive,
                                                                disallowAssistance: disallowAssistance) {
                        nodes.append(node)
                    }
                }
                if !disallowOffensive {
                    for droneID in session.pointee.entities.drones(on: otherHull) {
                        guard let target = session.pointee.entities[droneID]?.kind.drone?.target,
                              target != .invalid, target.hull == entityID else { continue }
                        let drone = Drone(session: session, id: DroneID(rawValue: droneID))
                        if let node = drone.projectedCapacitorNode(disallowOffensive: disallowOffensive,
                                                                   disallowAssistance: disallowAssistance) {
                            nodes.append(node)
                        }
                    }
                }
            }
        }

        /// Capacitor stability result.
        public func capacitor() -> CapacitorSimulator.Result {
            capacitorSimulator().run()
        }

        // MARK: - Heat

        /// Racks that can overheat.
        private static let heatedSlots: [Entity.Module.Slot] = [.hi, .med, .low]

        /// Overheat simulator. Collects full hi/med/low racks, not just overloaded modules:
        /// the slot fill ratio is ship-wide and includes rig slots in the denominator.
        /// Modules whose socket is outside the rack (overfitted) are skipped.
        @SnapshotField
        public func heatSimulator() -> HeatSimulator {
            var racks: [HeatSimulator.Rack] = []
            racks.reserveCapacity(3)

            for slot in Self.heatedSlots {
                guard let ids = slot.heatAttributeIDs else { continue }
                let total = Int(attributes[slot.attributeID] ?? 0)
                guard total > 0 else { continue }

                var sockets = [HeatSimulator.Socket](repeating: .empty, count: total)
                var nodes: [HeatSimulator.Node] = []
                modules.forEach(in: slot) { module in
                    let socket = module.socket
                    guard socket >= 0, socket < total else { return }
                    sockets[socket] = HeatSimulator.Socket(id: module.id,
                                                           hitPoints: module.attributes[.hp] ?? 0,
                                                           isOnline: module.effectiveState >= .online)
                    if let node = module.heatNode() { nodes.append(node) }
                }

                racks.append(HeatSimulator.Rack(slot: slot,
                                                capacity: attributes[ids.capacity, default: .sde] / 100,
                                                attenuation: attributes[ids.attenuation, default: .sde],
                                                dissipationRate: attributes[ids.dissipation, default: .sde],
                                                sockets: sockets,
                                                nodes: nodes))
            }

            return HeatSimulator(heatGenerationMultiplier: attributes[.heatGenerationMultiplier, default: .sde],
                                 racks: racks,
                                 rigSlots: Int(attributes[Entity.Module.Slot.rig.attributeID] ?? 0))
        }

        /// Overheat simulation result: how long each module survives.
        public func heat() -> HeatSimulator.Result {
            heatSimulator().run()
        }

        /// Warfare buffs currently applied to this hull and its modules, drones and charges,
        /// sorted by ID. Only live sources count: a burst must be active and the hull must not
        /// be under a disallow mask that blocks the buff.
        public var warfareBuffs: [FitStats.WarfareBuff] {
            let session = self.session
            let context = session.pointee.context
            let pilot = entityID.pilot

            var sources: [WarfareBuffID: Set<AttributeKey>] = [:]
            for modifier in context.modifiers where modifier.buffID.rawValue != 0 {
                guard modifier.target.entityID.pilot == pilot, context.isAlive(modifier) else { continue }
                sources[modifier.buffID, default: []].insert(modifier.source)
            }

            return sources
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .compactMap { session.pointee.warfareBuff($0.key, from: $0.value) }
        }

        // MARK: - Tank

        /// All repairs applied to this hull: own active local repairers plus incoming
        /// remote reps. Capacitor use is always computed with `reload.forCapacitor`.
        func tankProfile(reload: ReloadPolicy) -> TankProfile {
            var repairers: [TankProfile.Repairer] = []
            for slot in Self.activeModuleSlots {
                modules.forEach(in: slot) { module in
                    guard let repair = module.repair(reload: reload), !repair.isRemote else { return }
                    repairers.append(.init(kind: repair.kind,
                                           hpPerSecond: repair.hpPerSecond,
                                           capPerSecond: max(0, module.capUse(reload: reload.forCapacitor))))
                }
            }
            appendIncomingRepairers(into: &repairers, reload: reload)
            return TankProfile(passiveShield: passiveShieldRecharge, repairers: repairers)
        }

        /// Incoming remote reps are skipped when the target disallows assistance.
        private func appendIncomingRepairers(into repairers: inout [TankProfile.Repairer], reload: ReloadPolicy) {
            let bit = UInt8(1) << entityID.pilotID
            guard (session.pointee.context.disallowAssistanceMask & bit) == 0 else { return }
            let myPilot = id.pilot

            for otherHull in session.pointee.entities.hulls() where otherHull.pilot != myPilot.rawValue {
                for moduleID in session.pointee.entities.modules(on: otherHull) {
                    guard let target = session.pointee.entities[moduleID]?.kind.module?.target,
                          target != .invalid, target.hull == entityID else { continue }
                    let module = Module(session: session, id: ModuleID(rawValue: moduleID))
                    guard let repair = module.repair(reload: reload), repair.isRemote else { continue }
                    repairers.append(.init(kind: repair.kind,
                                           hpPerSecond: repair.hpPerSecond,
                                           capPerSecond: 0))
                }
            }
        }

        /// Peak passive shield regen, HP/s: `2.5 · shieldCapacity / shieldRechargeRate`.
        private var passiveShieldRecharge: Double {
            let rechargeTime = attributes[.shieldRechargeRate, default: .sde] / 1000
            guard rechargeTime > 0 else { return 0 }
            return 2.5 * (attributes[.shieldCapacity] ?? 0) / rechargeTime
        }

        /// Hull tank, HP/s: passive shield regen plus all active local and incoming
        /// remote repairers. Respects the reload policy: ancillary repairers spread the
        /// reload over the cycle, `.ignored` gives burst tank.
        @SnapshotField
        public func tank() -> Tank {
            tankProfile(reload: session.pointee.reload).tank
        }

        /// Tank inputs under `ReloadPolicy.forCapacitor`: the input of `sustainableTank`.
        /// Equals the profile behind `tank()` unless the read ignores reloads.
        @SnapshotField
        public func tankProfile() -> TankProfile {
            tankProfile(reload: session.pointee.reload.forCapacitor)
        }

        /// Tank the capacitor can sustain indefinitely. Equals `tank` when the capacitor
        /// is stable. Otherwise capacitor-using local repairers are added greedily by
        /// HP per capacitor unit while peak recharge allows; the last one may run
        /// partially. Uses `ReloadPolicy.forCapacitor`.
        public func sustainableTank() -> Tank {
            sustainableTank(capacitor: capacitor())
        }

        /// Same as `sustainableTank()`, reusing an already computed `capacitor()` result.
        public func sustainableTank(capacitor cap: CapacitorSimulator.Result) -> Tank {
            tankProfile().sustainableTank(capacitor: cap)
        }
    }
    
    
}
