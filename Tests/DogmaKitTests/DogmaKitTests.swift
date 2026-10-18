import Testing
@testable import DogmaKit
@testable import DogmaText

struct SetupDebugNamesTrait: SuiteTrait, TestScoping {
    private actor Guard {
        static let shared = Guard()
        var catalog: TextCatalog?
        func runOnce() {
            guard catalog == nil else { return }
            catalog = try! TextCatalog.installAsDebugNames()
        }
    }
    
    func provideScope(for test: Test, testCase: Test.Case?, performing function: () async throws -> Void) async throws {
        await Guard.shared.runOnce()
        try await function()
    }
}

// Convenience extension for nicer trait syntax
extension Trait where Self == SetupDebugNamesTrait {
    static var setupDebugNames: Self { SetupDebugNamesTrait() }
}

// Smoke tests of the public DogmaEngine API (configure/calculate): the engine builds a fit,
// runs the fixed point and returns stats without crashing. Calculation accuracy is not checked here.

@Suite("DogmaEngine basics", .setupDebugNames)
struct DogmaEngineTests {

    @Test("An empty engine calculates without crashing")
    func emptyCalculate() async throws {
        let engine = DogmaEngine()
        let pilotCount = await engine.evaluate { stats in
            stats.pilots.count
        }
        #expect(pilotCount == 0)
    }

    @Test("pilots.add creates a pilot with a capsule hull by default")
    func pilotsAddCreatesPilotAndCapsule() async throws {
        let engine = DogmaEngine()
        // The default hull is a capsule (checked on the write side).
        let defaultHull: TypeID = try await engine.edit { fit -> TypeID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            return hull.typeID
        }
        #expect(defaultHull == .capsule)

        // Exactly one pilot (checked on the read side).
        let pilotCount = await engine.evaluate { stats in
            stats.pilots.count
        }
        #expect(pilotCount == 1)
    }

    @Test("Several pilots exist independently")
    func multiplePilots() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            try fit.pilots.add(skillLevel: 5)
            try fit.pilots.add(skillLevel: 3)
        }
        let count = await engine.evaluate { stats in
            stats.pilots.count
        }
        #expect(count == 2)
    }

    @Test("set(typeID:) sets the ship hull")
    func setHullTypeID() async throws {
        let engine = DogmaEngine()
        let typeID: TypeID = try await engine.edit { fit -> TypeID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            return hull.typeID
        }
        #expect(typeID == .rifter)
    }

    @Test("An invalid hull typeID throws DogmaError")
    func setHullInvalidTypeThrows() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                // A typeID that certainly does not exist.
                try hull.set(typeID: TypeID(rawValue: .max))
            }
        }
    }

    @Test("modules.add puts modules into the right slots")
    func modulesAddAppearsInSlot() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.modules.add(.warpScramblerII)   // med
            try hull.modules.add(.damageControlII)   // low
        }
        let (med, low) = await engine.evaluate { stats -> (Int, Int) in
            let hull = stats[PilotID(1).hull]
            return (hull.modules.count(in: .med), hull.modules.count(in: .low))
        }
        #expect(med == 1)
        #expect(low == 1)
    }

    @Test("Module state is written and read back")
    func moduleStateRoundTrip() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.sensorBoosterII)
            module.state = .active
            #expect(module.state == .active)
        }
        let state = await engine.evaluate { stats -> Entity.Module.State in
            let hull = stats[PilotID(1).hull]
            let id = Array(hull.modules.ids(in: .med)).first!
            return hull.modules[id].state
        }
        #expect(state == .active)
    }

    @Test("A module has an effectiveState after calculate")
    func effectiveStateResolved() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.sensorBoosterII)
            module.state = .online
        }
        let effective = await engine.evaluate { stats -> Entity.Module.State in
            let hull = stats[PilotID(1).hull]
            let id = Array(hull.modules.ids(in: .med)).first!
            return hull.modules[id].effectiveState
        }
        // effectiveState cannot exceed the requested online.
        #expect(effective <= .online)
    }

    @Test("setCharge loads a charge into a module")
    func setChargeLoadsCharge() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.sensorBoosterII)
            module.state = .online
            try module.setCharge(.scanResolutionScript)
            let hasCharge = module.charge != nil
            #expect(hasCharge)
        }
        let hasCharge = await engine.evaluate { stats -> Bool in
            let hull = stats[PilotID(1).hull]
            let id = Array(hull.modules.ids(in: .med)).first!
            let module = hull.modules[id]
            return module.charge != nil
        }
        #expect(hasCharge)
    }

    @Test("remove() removes the module from the fit")
    func removeModule() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.warpScramblerII)
            module.remove()
        }
        let count = await engine.evaluate { stats -> Int in
            let hull = stats[PilotID(1).hull]
            return hull.modules.count(in: .med)
        }
        #expect(count == 0)
    }

    @Test("A missing module throws DogmaError")
    func modulesAddInvalidTypeThrows() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .rifter)
                try hull.modules.add(TypeID(rawValue: .max))
            }
        }
    }

    @Test("drones.add adds a drone")
    func dronesAdd() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.drones.add(.hobgoblinII)
        }
        let count = await engine.evaluate { stats -> Int in
            let hull = stats[PilotID(1).hull]
            return hull.drones.count
        }
        #expect(count == 1)
    }

    @Test("Base hull HP is available after calculation")
    func hullStatsReadable() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        }
        let hp = await engine.evaluate { stats -> Double in
            let hull = stats[PilotID(1).hull]
            return hull.hitPoints.shield + hull.hitPoints.armor + hull.hitPoints.hull
        }
        // Only checks that the ship has HP at all, not accuracy.
        #expect(hp > 0)
    }

    @Test("Repeated calculate is stable (fixed point converges)")
    func repeatedCalculate() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.sensorBoosterII)
            module.state = .active
        }
        let a = await engine.evaluate { stats -> Double in
            let hull = stats[PilotID(1).hull]
            return hull.hitPoints.shield
        }
        let b = await engine.evaluate { stats -> Double in
            let hull = stats[PilotID(1).hull]
            return hull.hitPoints.shield
        }
        #expect(a == b)
    }
}

// Tests that the engine really applies modifiers: active modules, passive bonuses and
// skills change hull attributes. Exact numbers are not checked, only that the value
// differs from the unmodified base.

@Suite("DogmaEngine modifiers", .setupDebugNames)
struct DogmaEngineModifierTests {

    /// A hull attribute of the first pilot after calculation (with the SDE default value).
    private func hullAttribute(_ engine: DogmaEngine, _ attribute: AttributeID) async -> Double {
        await engine.evaluate { stats -> Double in
            let hull = stats[PilotID(1).hull]
            return hull.attributes[attribute, default: .sde]
        }
    }

    /// A bare Rifter without modules (pilot at skill 5), the base for comparison.
    private func makeBareRifter() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        }
        return engine
    }

    @Test("An active afterburner increases maximum velocity")
    func afterburnerBoostsVelocity() async throws {
        let base = try await makeBareRifter()
        let baseVelocity = await hullAttribute(base, .maxVelocity)

        let boosted = DogmaEngine()
        try await boosted.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let ab = try hull.modules.add(._1MNAfterburnerI)
            ab.state = .active
        }
        let boostedVelocity = await hullAttribute(boosted, .maxVelocity)

        #expect(baseVelocity > 0)
        #expect(boostedVelocity > baseVelocity)
    }

    @Test("An armor plate increases armor HP")
    func armorPlateIncreasesArmorHP() async throws {
        let base = try await makeBareRifter()
        let baseArmor = await hullAttribute(base, .armorHP)

        let plated = DogmaEngine()
        try await plated.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let plate = try hull.modules.add(._100mmSteelPlatesII)
            plate.state = .online
        }
        let platedArmor = await hullAttribute(plated, .armorHP)

        #expect(baseArmor > 0)
        #expect(platedArmor > baseArmor)
    }

    @Test("Damage Control raises armor resistance (lowers resonance)")
    func damageControlImprovesResists() async throws {
        let base = try await makeBareRifter()
        let baseResonance = await hullAttribute(base, .armorEmDamageResonance)

        let hardened = DogmaEngine()
        try await hardened.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let dc = try hull.modules.add(.damageControlII)
            dc.state = .online
        }
        let hardenedResonance = await hullAttribute(hardened, .armorEmDamageResonance)

        // Resonance = (1 - resist). Higher resist => lower resonance.
        #expect(hardenedResonance < baseResonance)
    }

    @Test("Hull resistances are read through Resistances")
    func resistancesReflectModule() async throws {
        let base = try await makeBareRifter()
        let baseArmorEm = await base.evaluate { stats -> Double in
            stats[PilotID(1).hull].resistances.armor.em
        }

        let hardened = DogmaEngine()
        try await hardened.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let dc = try hull.modules.add(.damageControlII)
            dc.state = .online
        }
        let hardenedArmorEm = await hardened.evaluate { stats -> Double in
            stats[PilotID(1).hull].resistances.armor.em
        }

        #expect(hardenedArmorEm > baseArmorEm)
    }

    @Test("Skills affect ship attributes (navigation -> velocity)")
    func skillLevelAffectsAttributes() async throws {
        let untrained = DogmaEngine()
        try await untrained.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 0)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        }
        let velocity0 = await hullAttribute(untrained, .maxVelocity)

        let trained = DogmaEngine()
        try await trained.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        }
        let velocity5 = await hullAttribute(trained, .maxVelocity)

        // Navigation (+% velocity per level) makes velocity higher with trained skills.
        #expect(velocity5 > velocity0)
    }

    @Test("An inactive module has no effect (offline)")
    func offlineModuleHasNoEffect() async throws {
        let base = try await makeBareRifter()
        let baseVelocity = await hullAttribute(base, .maxVelocity)

        let withOfflineAB = DogmaEngine()
        try await withOfflineAB.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        // The afterburner is added but left offline, so its speed boost must not apply.
            let module = try hull.modules.add(._1MNAfterburnerI)
            module.state = .offline
        }
        let offlineVelocity = await hullAttribute(withOfflineAB, .maxVelocity)

        #expect(offlineVelocity == baseVelocity)
    }
}
