//
//  ContextBuilder.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 18.06.2026.
//

import DogmaModels

struct Registry<Value> {
    typealias Key = AttributeKey
    struct ListHeader {
        var head: Int32
        var tail: Int32
    }
    struct Node {
        var next: Int32
        var value: Value
    }
    var lists: AttributeRegistry<ListHeader>
    var nodes: [Node] = []
    
    @inlinable
    init() {
        lists = AttributeRegistry()
    }
    
    /// Resets the registry for the current set of entities.
    @inlinable
    mutating func reset(for entities: EntityStore) {
        lists.reset(for: entities)
        nodes.removeAll(keepingCapacity: true)
        nodes.reserveCapacity(entities.count * 20)
    }
    
    @inlinable
    mutating func append(_ value: Value, for key: Key) {
        let node = Node(next: -1, value: value)
        let idx = Int32(nodes.count)
        nodes.append(node)
        
        func update(_ list: inout ListHeader?) {
            if let tail = list?.tail {
                nodes[Int(tail)].next = idx
                list?.tail = idx
            }
            else {
                list = ListHeader(head: idx, tail: idx)
            }
        }
        
        update(&lists[key])
    }
    
    @inlinable
    subscript(key: Key) -> List? {
        get {
            guard let list = lists[key] else {return nil}
            return List(head: list.head, nodes: nodes)
        }
        set {
            precondition(newValue == nil)
            lists[key] = nil
        }
    }
    
    @inlinable
    public var last: (Key, List)? {
        guard let (key, list) = lists.last else {return nil}
        return (key, List(head: list.head, nodes: nodes))
    }
}

extension Registry {
    struct List: Sequence {
        var head: Int32
        var nodes: [Node]
        
        func makeIterator() -> Iterator {
            Iterator(idx: head, nodes: nodes)
        }
        
        struct Iterator: IteratorProtocol {
            var idx: Int32
            var nodes: [Node]
            mutating func next() -> Value? {
                guard idx != -1 else { return nil }
                let node = nodes[Int(idx)]
                idx = node.next
                return node.value
            }
        }
    }
}

struct ContextBuilder {
    typealias Key = AttributeKey
    typealias Modifiers = Registry<Modifier>

    var modifiers: Modifiers
    private var groupCounter = GroupCounter()

    init(entities: Int = 0) {
        modifiers = .init()
    }

    /// Builds the context for a new fixed-point pass: optimistic `effectiveState`
    /// (`min(state, maxAllowedState)`) and the full superset of modifiers, once per calculation.
    /// The entity store is read-only: `effectiveState` is written to the context.
    mutating func build(in session: inout DogmaEngine.Session) {
        session.context.disallowAssistanceMask = 0
        session.context.disallowOffensiveMask = 0

        collectModifiers(in: &session)
    }

    /// Active effect categories of an entity, based on `effectiveState` from the context.
    private func effectiveActiveEffects(of entity: borrowing Entity, using session: borrowing DogmaEngine.Session) -> DogmaSDE.Effect.Category {
        switch entity.kind {
        case .module:
            return session.context[effectiveState: entity.id].effectCategories
        case let .drone(drone):
            // Drones apply effects only when deployed; in the bay they apply nothing,
            // not even passive effects.
            return drone.flags.isActive ? [.passive, .online, .activation, .target] : []
        case .charge:
            return effectiveActiveEffects(of: session.entities[entity.id.parent]!, using: session)
        case .environment:
            return [.passive, .environment, .dungeon, .system]
        default:
            return [.passive]
        }
    }

    /// Resets attributes to their base type values before the next evaluator pass.
    ///
    /// The only place where the engine knows about mutaplasmids: a mutation only replaces
    /// base attribute values. Three layers, in order: base type, the resulting type's own
    /// attributes, rolls. Clamps (`min/maxAttributeID`) and stacking penalties work on top.
    func reloadBaseAttributes(in session: inout DogmaEngine.Session) {
        session.context.attributes.reset(for: session.entities)
        let sde = session.sde
        for entity in session.entities {
            if let mutation = entity.mutation {
                sde[mutation.baseType].attributes.forEach { attribute in
                    let attributeID = attribute.key.load()
                    let value = attribute.value.load()
                    session.context.attributes[Modifiers.Key(entityID: entity.id, attributeID: attributeID)] = Double(value)
                }
            }

            let type = sde[entity.typeID]!
            type.attributes.forEach { attribute in
                let attributeID = attribute.key.load()
                let value = attribute.value.load()
                session.context.attributes[Modifiers.Key(entityID: entity.id, attributeID: attributeID)] = Double(value)
            }

            if entity.mutation != nil, let rolls = session.entities.rolls(for: entity.id) {
                for roll in rolls {
                    session.context.attributes[Modifiers.Key(entityID: entity.id, attributeID: roll.attributeID)] = roll.value
                }
            }

            if let skillLevel = entity.kind.skillLevel {
                session.context.attributes[Modifiers.Key(entityID: entity.id, attributeID: .skillLevel)] = Double(skillLevel)
            }
        }
    }

    private mutating func collectModifiers(in session: inout DogmaEngine.Session) {
        modifiers.reset(for: session.entities)
        reloadBaseAttributes(in: &session)

        for entity in session.entities {
            if let module = entity.kind.module {
                session.context[effectiveState: entity.id] = min(module.state, module.flags.maxAllowedState)
            }

            
            let activeEffects = effectiveActiveEffects(of: entity, using: session)
            let type = session.sde[entity.typeID]!

            type.effects.forEach { effect in
                let category = effect.category.load()
                guard activeEffects.contains(category) else {return}
                let options = effect.options.load()
                let minSourceState = Self.minSourceState(for: category, of: entity)

                // Warfare buff marker effects carry no modifiers of their own: the list
                // comes from the warfareBuffs table by the IDs in the source's attributes.
                switch effect.id.load() {
                case .gangBoost, .environmentBoost:
                    collectWarfareBuffs(of: entity,
                                        minSourceState: minSourceState,
                                        options: options,
                                        in: session)
                    return
                default:
                    break
                }

                effect.modifiers.forEach {
                    let mod = $0.load()

                    if mod.domain == .target {
                        guard let target = entity.kind.module?.target ?? entity.kind.drone?.target, target != .invalid else {return}
                    }

                    let isStackable = entity.categoryID.isStackable ||
                    mod.operation.isStackable ||
                    session.sde[mod.modifiedAttributeID]!.options.load().contains(.isStackable)

                    emit(mod,
                         of: entity,
                         source: .init(entityID: entity.id, attributeID: mod.modifyingAttributeID),
                         minSourceState: minSourceState,
                         options: options,
                         needsStackingCheck: !isStackable,
                         in: session)
                }
            }
        }
        
        session.context.modifiers.removeAll(keepingCapacity: true)
        
        func extract(_ key: Modifiers.Key) {
            guard let list = modifiers[key] else { return }
            modifiers[key] = nil
            for modifier in list {
                switch modifier.operation {
                case .addRate, .subRate:
                    extract(.init(entityID: modifier.source.entityID, attributeID: .duration))
                    extract(.init(entityID: modifier.source.entityID, attributeID: .speed))
                default:
                    break
                }
                extract(modifier.source)
            }
            let from = session.context.modifiers.endIndex
            session.context.modifiers.append(contentsOf: list)
            let to = session.context.modifiers.endIndex
            session.context.modifiers.withUnsafeMutableBufferPointer { buffer in
                var tmp = UnsafeMutableBufferPointer(rebasing: buffer[from..<to])
                tmp.sort()
            }
        }
        
        while let (key, _) = modifiers.last {
            extract(key)
        }
    }

    /// Expands one SDE modifier over its targets (scope × domain) into the registry.
    /// `source` is the entity's `modifyingAttributeID` for regular effects and the
    /// carrier's `warfareBuff{N}Value` for warfare buffs.
    private mutating func emit(_ mod: DogmaSDE.Modifier,
                               of entity: Entity,
                               source: Key,
                               minSourceState: Entity.Module.State,
                               options: DogmaSDE.EffectOptions,
                               needsStackingCheck: Bool,
                               buffID: WarfareBuffID = 0,
                               aggregateMin: Bool = false,
                               in session: borrowing DogmaEngine.Session) {
        func apply(to target: EntityID) {
            // `collect` builds the full superset; disallow filtering and state gates are
            // applied inline in `AttributeCalculator`.
            var desc = Modifier(rawValue: 0)
            desc.isProjected = entity.id.pilot != target.pilot
            desc.isOffensive = options.contains(.isOffensive)
            desc.isAssistance = options.contains(.isAssistance)
            desc.minSourceState = minSourceState
            desc.source = source
            desc.target = .init(entityID: target, attributeID: mod.modifiedAttributeID)
            desc.operation = mod.operation
            desc.needsStackingCheck = needsStackingCheck
            desc.buffID = buffID
            desc.aggregateMin = aggregateMin
            modifiers.append(desc, for: desc.target)
        }

        for domain in mod.domain.resolve(for: entity, from: session.entities) {
            switch mod.scope {
            case .item:
                apply(to: domain)
            case .location:
                for id in location(in: domain, from: session.entities) {
                    apply(to: id)
                }

            case let .locationGroup(groupID):
                for id in locationGroup(groupID, in: domain, from: session.entities) {
                    apply(to: id)
                }
            case .locationRequiredDomainSkill:
                // The skill itself is the required skill. Pilot-domain bonuses (drone and
                // missile damage skills) target what the pilot owns: drones and loaded charges,
                // which live on the hull, not the pilot's implants and boosters.
                if domain.category == .pilot {
                    for id in ownerRequiredSkill(entity.typeID, in: domain, using: session) {
                        apply(to: id)
                    }
                } else {
                    for id in locationRequiredSkill(entity.typeID, in: domain, using: session) {
                        apply(to: id)
                    }
                }
            case let .locationRequiredSkill(skillID):
                for id in locationRequiredSkill(skillID, in: domain, using: session) {
                    apply(to: id)
                }
            case let .ownerRequiredSkill(skillID):
                for id in ownerRequiredSkill(skillID, in: domain, using: session) {
                    apply(to: id)
                }
            }
        }
    }

    /// Warfare buff slots: buff ID attribute and the attribute carrying its value.
    private static let warfareBuffSlots: [(id: AttributeID, value: AttributeID)] = [
        (.warfareBuff1ID, .warfareBuff1Value),
        (.warfareBuff2ID, .warfareBuff2Value),
        (.warfareBuff3ID, .warfareBuff3Value),
        (.warfareBuff4ID, .warfareBuff4Value),
    ]

    /// Distributes the source's warfare buffs (command bursts with a charge, phenomena
    /// generators, environment effects) to the whole fleet.
    ///
    /// The buff ID is read from base type attributes, not the context: at runtime it is only
    /// copied by the charge, so it is known before calculation. Otherwise the graph structure
    /// would depend on results, and later fixed-point passes would have to add modifiers,
    /// breaking monotonicity. The charge takes priority over the carrier (no SDE type has both).
    ///
    /// The value comes from the context (carrier, `warfareBuff{N}Value`), with the charge
    /// multiplier, skills, hull and mindlink bonuses already applied; the topological order
    /// in `extract` computes it before its dependents.
    ///
    /// Warfare bonuses are not stacking penalized.
    private mutating func collectWarfareBuffs(of entity: Entity,
                                             minSourceState: Entity.Module.State,
                                             options: DogmaSDE.EffectOptions,
                                             in session: borrowing DogmaEngine.Session) {
        let charge = entity.id.category == .module ? session.entities[.charge(in: entity.id)] : nil

        for slot in Self.warfareBuffSlots {
            var rawID: Float? = nil
            if let charge {
                rawID = session.sde[charge.typeID]!.attributes[slot.id]?.load()
            }
            if (rawID ?? 0) == 0 {
                rawID = session.sde[entity.typeID]!.attributes[slot.id]?.load()
            }
            guard let rawID, rawID > 0 else { continue }

            let buffID = WarfareBuffID(rawValue: UInt16(rawID))
            guard let buff = session.sde[buffID] else { continue }

            let info = buff.info.load()
            let source = Key(entityID: entity.id, attributeID: slot.value)
            buff.modifiers.forEach {
                emit($0.load(),
                     of: entity,
                     source: source,
                     minSourceState: minSourceState,
                     options: options,
                     needsStackingCheck: false,
                     buffID: buffID,
                     aggregateMin: info.aggregateMode == .minimum,
                     in: session)
            }
        }
    }

    /// Minimum source module state at which an effect of this category is alive.
    /// Always `.offline` for sources whose activity does not depend on module state.
    private static func minSourceState(for category: DogmaSDE.Effect.Category, of entity: Entity) -> Entity.Module.State {
        switch entity.kind {
        case .module, .charge:
            return category.minState
        default:
            return .offline
        }
    }

    /// Applies gates to effective states using computed attributes. Returns `true` if
    /// something changed and another pass is needed. Monotonic: states only go down and
    /// disallow masks only grow, so the set of live modifiers only shrinks and the graph
    /// does not need to be rebuilt.
    mutating func resolveStates(in session: inout DogmaEngine.Session) -> Bool {
        var changed = false

        // 1. Disallow masks: from the hull itself or an active module on it.
        var offensiveMask = session.context.disallowOffensiveMask
        var assistanceMask = session.context.disallowAssistanceMask
        for entity in session.entities {
            switch entity.kind {
            case .module:
                guard session.context[effectiveState: entity.id] >= .active else { continue }
            case .ship:
                break
            default:
                continue
            }
            let bit = UInt8(1) << entity.id.pilotID
            if let value = session.context.attributes[.init(entityID: entity.id, attributeID: .disallowOffensiveModifiers)], value > 0 {
                offensiveMask |= bit
            }
            if let value = session.context.attributes[.init(entityID: entity.id, attributeID: .disallowAssistance)], value > 0 {
                assistanceMask |= bit
            }
        }
        if offensiveMask != session.context.disallowOffensiveMask || assistanceMask != session.context.disallowAssistanceMask {
            session.context.disallowOffensiveMask = offensiveMask
            session.context.disallowAssistanceMask = assistanceMask
            changed = true
        }

        // 2. Module state gates. Traversal order is deterministic (slots in order, fit order
        // within a slot): when a limit is exceeded the first N modules keep their state and
        // the rest are demoted. maxGroupFitted/maxTypeFitted do not demote; they are fitting errors.
        for hull in session.entities.hulls() {
            groupCounter.reset()

            for id in session.entities.modules(on: hull) {
                guard let entity = session.entities[id], entity.kind.module != nil else { continue }
                let initialState = session.context[effectiveState: id]
                var state = initialState
                guard state >= .online else { continue }

                let slot = groupCounter.index(for: entity.groupID.rawValue)

                if state >= .active,
                   let activationBlocked = session.context.attributes[.init(entityID: id, attributeID: .activationBlocked)],
                   activationBlocked > 0 {
                    state = .online
                }

                if let maxOnline = session.context.attributes[.init(entityID: id, attributeID: .maxGroupOnline)],
                   maxOnline > 0,
                   groupCounter.onlineCount(at: slot) >= Int(maxOnline) {
                    state = .offline
                }

                if state >= .active,
                   let maxActive = session.context.attributes[.init(entityID: id, attributeID: .maxGroupActive)],
                   maxActive > 0,
                   groupCounter.activeCount(at: slot) >= Int(maxActive) {
                    state = .online
                }

                if state >= .online { groupCounter.incrementOnline(slot) }
                if state >= .active { groupCounter.incrementActive(slot) }

                if state != initialState {
                    session.context[effectiveState: id] = state
                    changed = true
                }
            }
        }
        return changed
    }

    @inlinable
    func location(in domain: EntityID, from entities: borrowing EntityStore) -> some Sequence<EntityID> {
        entities.modules(on: domain.hull)
    }
    
    @SequenceBuilder<EntityID>
    @inlinable
    func locationGroup(_ groupID: GroupID, in domain: EntityID, from entities: borrowing EntityStore) -> some Sequence<EntityID> {
        switch domain.category {
        case .pilot:
            entities.ids(in: .booster(for: domain))
                .chained(with: entities.ids(in: .implant(for: domain)))
                .locationGroup(groupID, from: entities)
        case .hull:
            // Loaded charges are located in the ship too (e.g. force auxiliary bonuses to the
            // Capacitor Booster Charge group).
            entities.modules(on: domain)
                .chained(with: entities.drones(on: domain))
                .chained(with: entities.charges(on: domain))
                .locationGroup(groupID, from: entities)
        default:
            EmptyCollection()
        }
    }
    
    @SequenceBuilder<EntityID>
    @inlinable
    func locationRequiredSkill(_ skill: TypeID, in domain: EntityID, using session: borrowing DogmaEngine.Session) -> some Sequence<EntityID> {
        switch domain.category {
        case .pilot:
            session.entities.ids(in: .booster(for: domain))
                .chained(with: session.entities.ids(in: .implant(for: domain)))
                .locationRequiredSkill(skill, from: session.entities, using: session.sde)
        case .hull:
            // Loaded charges are located in the ship too (e.g. Jackdaw/Skua Sharpshooter Mode
            // missile damage). Drones are not: bonuses meant for them are owner-required
            // (`ownerRequiredSkill`), while ship-located Mining bonuses must not reach mining drones.
            session.entities.modules(on: domain)
                .chained(with: session.entities.charges(on: domain))
                .locationRequiredSkill(skill, from: session.entities, using: session.sde)
        default:
            EmptyCollection()
        }
    }
    
    @inlinable
    func ownerRequiredSkill(_ skill: TypeID, in domain: EntityID, using session: borrowing DogmaEngine.Session) -> some Sequence<EntityID> {
        let hull = EntityID.hull(for: domain)
        return session.entities.drones(on: hull)
            .chained(with: session.entities.charges(on: hull))
            .locationRequiredSkill(skill, from: session.entities, using: session.sde)
    }
}


extension CategoryID {
    @inlinable
    var isStackable: Bool {
        switch self {
        case .module, .drone, .fighter, .charge, .structure, .structureModule:
            false
        default:
            true
        }
    }
}

extension DogmaSDE.Modifier.Operation {
    var isStackable: Bool {
        switch self {
        case .preMul, .postMul, .preDiv, .postDiv, .postPercent:
            false
        default:
            true
        }
    }
}

/// Flat per-hull group counter (open addressing, power-of-two mask) holding both online
/// and active counts. Capacity 512 exceeds the worst case (64 × 7 = 448 modules per hull),
/// so probing always terminates.
struct GroupCounter {
    private var keys: ContiguousArray<Int32>
    private var onlineCounts: ContiguousArray<Int32>
    private var activeCounts: ContiguousArray<Int32>
    private let mask: Int

    init(capacity: Int = 512) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be a power of two")
        keys = ContiguousArray(repeating: -1, count: capacity)
        onlineCounts = ContiguousArray(repeating: 0, count: capacity)
        activeCounts = ContiguousArray(repeating: 0, count: capacity)
        mask = capacity - 1
    }

    /// Resets keys only; counters are zeroed lazily when a slot is claimed in `index(for:)`.
    mutating func reset() {
        keys.withUnsafeMutableBufferPointer { $0.update(repeating: -1) }
    }

    /// Slot index for a group; claims the slot and zeroes its counters on first access.
    mutating func index(for group: GroupID.RawValue) -> Int {
        let key = Int32(group)
        var i = Int(group) & mask
        while keys[i] != -1 {
            if keys[i] == key { return i }
            i = (i + 1) & mask
        }
        keys[i] = key
        onlineCounts[i] = 0
        activeCounts[i] = 0
        return i
    }

    @inline(__always) func onlineCount(at slot: Int) -> Int { Int(onlineCounts[slot]) }
    @inline(__always) func activeCount(at slot: Int) -> Int { Int(activeCounts[slot]) }
    @inline(__always) mutating func incrementOnline(_ slot: Int) { onlineCounts[slot] += 1 }
    @inline(__always) mutating func incrementActive(_ slot: Int) { activeCounts[slot] += 1 }
}

