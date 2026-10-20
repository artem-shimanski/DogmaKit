//
//  FitStats+Hull.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 05.07.2026.
//

import simd

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

    public struct Hull: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: HullID
        @inlinable var entityID: EntityID {id.rawValue}
        
        public let attributes: EntityAttributes
        
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

        public var modules: Modules {
            @_lifetime(borrow self) get {
                Modules(hull: self)
            }
        }

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

        private func forEachDamagingModule(in sources: DamageSource, _ body: (borrowing Module) -> Void) {
            guard !sources.isDisjoint(with: .modules) else { return }
            for slot in Self.damageSlots {
                modules.forEach(in: slot) { module in
                    guard sources.contains(module.hardpoint.damageSource) else { return }
                    body(module)
                }
            }
        }

        private func forEachDamagingDrone(in sources: DamageSource, _ body: (borrowing Drone) -> Void) {
            guard !sources.isDisjoint(with: .deployables) else { return }
            drones.forEach { drone in
                let source: DamageSource = drone.squadron == .none ? .drones : .fighters
                guard sources.contains(source) else { return }
                body(drone)
            }
        }

        /// Total DPS of the hull from the given source categories.
        /// `target == .zero` gives raw DPS with no tracking, range or missile flight penalties.
        /// Modules count only when `effectiveState >= .active`, drones only when `isActive`.
        public func dps(from sources: DamageSource = .all,
                        to target: Target = .zero) -> DamageVector {
            var result = DamageVector.zero
            forEachDamagingModule(in: sources) { result += $0.dps(to: target) }
            forEachDamagingDrone(in: sources) { result += $0.dps(to: target) }
            return result
        }

        /// Total volley (alpha strike) of the hull from the given source categories:
        /// damage of one cycle of every weapon fired at once.
        public func volleyDamage(from sources: DamageSource = .all,
                                 to target: Target = .zero) -> DamageVector {
            var result = DamageVector.zero
            forEachDamagingModule(in: sources) { result += $0.volleyDamage(to: target) }
            forEachDamagingDrone(in: sources) { result += $0.volleyDamage(to: target) }
            return result
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

        /// Drone bay: `used` is the volume of all stacks (drones in space still occupy
        /// bay space), `total` is the hull's `droneCapacity`.
        public var droneBay: Resource {
            var used: Double = 0
            drones.forEach { drone in
                used += (drone.attributes[.volume] ?? 0) * Double(drone.count)
            }
            return Resource(used: used, total: attributes[.droneCapacity] ?? 0)
        }

        /// Drone bandwidth: only drones in space use it, so `used` counts active stacks only.
        public var droneBandwidth: Resource {
            var used: Double = 0
            drones.forEach { drone in
                guard drone.isActive else { return }
                used += (drone.attributes[.droneBandwidthUsed] ?? 0) * Double(drone.count)
            }
            return Resource(used: used, total: attributes[.droneBandwidth] ?? 0)
        }

        /// Drones in space. `total` is the pilot's `maxActiveDrones` (a pilot attribute, not a hull one).
        public var dronesInSpace: SlotCapacity {
            var used = 0
            drones.forEach { drone in
                guard drone.isActive else { return }
                used += drone.count
            }
            let pilot = Pilot(session: session, id: id.pilot)
            return SlotCapacity(used: used, total: Int(pilot.attributes[.maxActiveDrones] ?? 0))
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
            Targeting(maxTargetRange: attributes[.maxTargetRange] ?? 0,
                      scanResolution: attributes[.scanResolution] ?? 0,
                      maxLockedTargets: Int(attributes[.maxLockedTargets] ?? 0),
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

        // MARK: - Tank

        /// One repair contribution. `capPerSecond == 0` means the repairer does not use
        /// this ship's capacitor (incoming remote reps, capless reps); `sustainableTank`
        /// never throttles those.
        struct Repairer {
            var kind: Module.RepairKind
            var hpPerSecond: Double
            var capPerSecond: Double

            /// HP per unit of capacitor; the greedy order in `sustainableTank`.
            var effectivity: Double { hpPerSecond / capPerSecond }
        }

        /// All repairs applied to this hull: own active local repairers plus incoming
        /// remote reps. Capacitor use is always computed with `reload.forCapacitor`.
        func repairers(reload: ReloadPolicy) -> [Repairer] {
            var result: [Repairer] = []
            for slot in Self.activeModuleSlots {
                modules.forEach(in: slot) { module in
                    guard let repair = module.repair(reload: reload), !repair.isRemote else { return }
                    result.append(Repairer(kind: repair.kind,
                                           hpPerSecond: repair.hpPerSecond,
                                           capPerSecond: max(0, module.capUse(reload: reload.forCapacitor))))
                }
            }
            appendIncomingRepairers(into: &result, reload: reload)
            return result
        }

        /// Incoming remote reps are skipped when the target disallows assistance.
        private func appendIncomingRepairers(into repairers: inout [Repairer], reload: ReloadPolicy) {
            let bit = UInt8(1) << entityID.pilotID
            guard (session.pointee.context.disallowAssistanceMask & bit) == 0 else { return }
            let myPilot = id.pilot

            for otherHull in session.pointee.entities.hulls() where otherHull.pilot != myPilot.rawValue {
                for moduleID in session.pointee.entities.modules(on: otherHull) {
                    guard let target = session.pointee.entities[moduleID]?.kind.module?.target,
                          target != .invalid, target.hull == entityID else { continue }
                    let module = Module(session: session, id: ModuleID(rawValue: moduleID))
                    guard let repair = module.repair(reload: reload), repair.isRemote else { continue }
                    repairers.append(Repairer(kind: repair.kind,
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
        public func tank() -> Tank {
            tank(repairers: repairers(reload: session.pointee.reload))
        }

        private func tank(repairers: [Repairer]) -> Tank {
            var result = Tank(passiveShield: passiveShieldRecharge,
                              shieldRepair: 0, armorRepair: 0, hullRepair: 0)
            for repairer in repairers {
                result[repair: repairer.kind] += repairer.hpPerSecond
            }
            return result
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
            let repairers = repairers(reload: session.pointee.reload.forCapacitor)
            var result = tank(repairers: repairers)
            guard !cap.isStable else { return result }

            var capUse = cap.averageDrain
            let capRecharge = cap.peakRecharge

            var throttled = repairers.filter { $0.capPerSecond > 0 }
            for repairer in throttled {
                result[repair: repairer.kind] -= repairer.hpPerSecond
                capUse -= repairer.capPerSecond
            }

            throttled.sort { $0.effectivity > $1.effectivity }
            for repairer in throttled {
                if capUse > capRecharge { break }
                let sustainability = min(1.0, (capRecharge - capUse) / repairer.capPerSecond)
                result[repair: repairer.kind] += repairer.hpPerSecond * sustainability
                capUse += repairer.capPerSecond
            }

            return result
        }
    }
    
    
}
