//
//  WarfareBuff.swift
//  DogmaKit
//

extension FitStats {

    /// A warfare buff: a command burst, a phenomena generator or an environment effect.
    ///
    /// Identical buffs do not add up: of several sources with the same `id` only the strongest
    /// applies (`aggregateMode`), and `value` is its value. `sources` lists every live source,
    /// strongest first.
    public struct WarfareBuff: Sendable, Hashable, Identifiable {

        /// An entity broadcasting the buff: a module (burst or phenomena generator) or an
        /// environment effect.
        public struct Source: Sendable, Hashable {
            public var entityID: EntityID
            public var typeID: TypeID
            /// The source's `warfareBuff{N}Value`, with charge, skill, hull and implant
            /// bonuses applied.
            public var value: Double
        }

        public var id: WarfareBuffID
        /// How `value` is applied to the affected attributes.
        public var operation: DogmaSDE.Modifier.Operation
        public var aggregateMode: DogmaSDE.WarfareBuff.AggregateMode
        public var visibility: DogmaSDE.WarfareBuff.Visibility
        /// Value of the strongest source, in the units of `operation`
        /// (a percentage for `postPercent`).
        public var value: Double
        public var sources: [Source]

        /// `value` as shown in the game UI: sign flipped for `inverted` buffs (a resonance
        /// reduction shown as a resistance bonus), `nil` for `hidden` service buffs.
        public var displayValue: Double? {
            switch visibility {
            case .normal: value
            case .inverted: -value
            case .hidden: nil
            }
        }
    }
}

extension FitStats.Hull {
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
}

extension FitStats.Module {
    /// Warfare buffs the module broadcasts to the fleet while active, with its own values.
    /// Empty for modules that are not buff sources and for bursts without a charge.
    public var warfareBuffs: [FitStats.WarfareBuff] {
        session.pointee.broadcastWarfareBuffs(of: entityID)
    }
}

extension FitStats.EnvironmentEffect {
    /// Warfare buffs the environment effect applies to every hull in the session.
    public var warfareBuffs: [FitStats.WarfareBuff] {
        session.pointee.broadcastWarfareBuffs(of: entityID)
    }
}

extension DogmaEngine.Session {

    /// Buffs the entity broadcasts, one source each.
    func broadcastWarfareBuffs(of entityID: EntityID) -> [FitStats.WarfareBuff] {
        guard let entity = entities[entityID],
              ContextBuilder.isWarfareBuffSource(sde[entity.typeID]!) else { return [] }

        var buffs: [FitStats.WarfareBuff] = []
        ContextBuilder.forEachWarfareBuff(of: entity, in: self) { buffID, valueAttributeID in
            let source = AttributeKey(entityID: entityID, attributeID: valueAttributeID)
            if let buff = warfareBuff(buffID, from: [source]) {
                buffs.append(buff)
            }
        }
        return buffs
    }

    /// Assembles a buff from its source keys (`warfareBuff{N}Value` of each carrier).
    /// `nil` if the buff is missing from the SDE.
    func warfareBuff(_ id: WarfareBuffID, from sourceKeys: Set<AttributeKey>) -> FitStats.WarfareBuff? {
        guard let buff = sde[id] else { return nil }
        let info = buff.info.load()

        var sources = sourceKeys.compactMap { key -> FitStats.WarfareBuff.Source? in
            guard let entity = entities[key.entityID] else { return nil }
            let value = context.attributes[key] ?? Double(sde[key.attributeID]?.defaultValue ?? 0)
            return .init(entityID: key.entityID, typeID: entity.typeID, value: value)
        }
        guard !sources.isEmpty else { return nil }

        // Strength is compared on the applied operand, as in `AttributeCalculator`:
        // for a division the larger raw value is the weaker one.
        let operation = info.operation
        let isStronger: (Double, Double) -> Bool = info.aggregateMode == .minimum ? (<) : (>)
        sources.sort { lhs, rhs in
            let l = AttributeCalculator.operand(lhs.value, for: operation)
            let r = AttributeCalculator.operand(rhs.value, for: operation)
            return l != r ? isStronger(l, r) : lhs.entityID.rawValue < rhs.entityID.rawValue
        }

        return .init(id: id,
                     operation: operation,
                     aggregateMode: info.aggregateMode,
                     visibility: info.visibility,
                     value: sources[0].value,
                     sources: sources)
    }
}
