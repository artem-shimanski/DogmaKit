//
//  CalculatorContext.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 18.06.2026.
//

import Foundation
import BitField
import DogmaModels

@BitField<UInt32>
public struct AttributeKey: Hashable, Sendable {
    @Bit(16) public var attributeID: AttributeID
    @Bit(16) public var entityID: EntityID
    
    @inlinable
    init(entityID: EntityID, attributeID: AttributeID) {
        rawValue = 0
        self.attributeID = attributeID
        self.entityID = entityID
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

@usableFromInline
struct CalculatorContext: Sendable {

    init() {
        modifiers.reserveCapacity(1000)
        effectiveStates = ContiguousArray(repeating: .offline, count: Int(EntityID.RawValue.max) + 1)
    }

    var modifiers: [Modifier] = []
    @usableFromInline var attributes: AttributeRegistry<Double> = .init()
    /// Module state allowed by the engine, indexed by `EntityID.rawValue`. Written only by
    /// `ContextBuilder`; kept in the context so the calculation never mutates the model.
    var effectiveStates: ContiguousArray<Entity.Module.State>
    /// One bit per pilot ID: the pilot's hull has disallowAssistance.
    var disallowAssistanceMask: UInt8 = 0
    /// One bit per pilot ID: the pilot's hull has disallowOffensiveModifiers.
    var disallowOffensiveMask: UInt8 = 0

    @inline(__always)
    subscript(effectiveState id: EntityID) -> Entity.Module.State {
        get { effectiveStates[Int(id.rawValue)] }
        set { effectiveStates[Int(id.rawValue)] = newValue }
    }

    /// Whether the modifier applies under the current states and masks: its source is not
    /// demoted below `minSourceState` (a charge is gated by its parent module) and a
    /// projected modifier's target is not under a disallow mask.
    @inline(__always)
    func isAlive(_ modifier: Modifier) -> Bool {
        if modifier.isProjected {
            let bit = UInt8(1) << modifier.target.entityID.pilotID
            if modifier.isOffensive && disallowOffensiveMask & bit != 0 { return false }
            if modifier.isAssistance && disallowAssistanceMask & bit != 0 { return false }
        }
        let minState: Entity.Module.State = modifier.minSourceState
        guard minState > .offline else { return true }
        var gateID = modifier.source.entityID
        gateID.chargeID = 0
        return effectiveStates[Int(gateID.rawValue)] >= minState
    }

    mutating func cleanUp() {
        modifiers.removeAll(keepingCapacity: true)
        disallowAssistanceMask = 0
        disallowOffensiveMask = 0
        // `attributes` is reset in `reloadBaseAttributes`; `effectiveStates` is
        // reinitialized by `build`, and stale slots are never read.
    }
}

@BitField<UInt128>
@usableFromInline
struct Modifier: Sendable, Hashable {
    @Bit(1)  var isProjected: Bool
    @Bit(1)  var isOffensive: Bool
    @Bit(1)  var isAssistance: Bool
    /// Minimum `effectiveState` of the source module (the parent module for a charge) at
    /// which the modifier is active; `.offline` means state-independent. Lets demotion
    /// filter the list without rebuilding the graph. Kept in low bits, outside the
    /// (target, operation, buffID, needsStackingCheck) grouping.
    @Bit(2)  var minSourceState: Entity.Module.State!
    /// Warfare buff aggregation: `true` takes the minimum, `false` the maximum
    /// (`WarfareBuff.Info.aggregateMode`). Below the grouping mask; the same for all
    /// modifiers of one buff.
    @Bit(1)  var aggregateMin: Bool
    @Bit(32) var source: AttributeKey
    @Bit(1)  var needsStackingCheck: Bool
    /// Warfare buff ID (0 for a regular effect modifier). Part of the grouping mask, so
    /// identical buffs do not add up but collapse to the strongest one.
    @Bit(16) var buffID: WarfareBuffID
    @Bit(8)  var operation: DogmaSDE.Modifier.Operation!
    @Bit(32) var target: AttributeKey
}

extension Modifier: Comparable {
    @inlinable
    static func < (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension AttributeKey: CustomDebugStringConvertible {
    /// `entity:attribute`, e.g. `pilot[1].hull:maxVelocity [37]`.
    public var debugDescription: String {
        "\(entityID):\(attributeID)"
    }
}

extension Modifier: CustomDebugStringConvertible {
    /// One-line "target ← operation ← source" with flags, e.g.:
    ///
    /// ```
    /// pilot[1].hull:maxVelocity ← postMul ← pilot[1].hull.module[med:0]:speedFactor (stacking, ≥active)
    /// pilot[1].hull:armorEmDamageResonance ← postPercent ← pilot[2].hull.module[hi:0]:warfareBuff1Value (buff 22, max, projected)
    /// ```
    ///
    /// Unrecognized operation or state bits print as `?`.
    @usableFromInline
    var debugDescription: String {
        let operation: DogmaSDE.Modifier.Operation? = self.operation
        var text = "\(target) ← \(operation.map { "\($0)" } ?? "?") ← \(source)"

        var flags: [String] = []
        if buffID.rawValue != 0 {
            flags.append("buff \(buffID)")
            flags.append(aggregateMin ? "min" : "max")
        }
        if needsStackingCheck { flags.append("stacking") }

        let minSourceState: Entity.Module.State? = self.minSourceState
        switch minSourceState {
        case .none:
            flags.append("≥?")
        case .some(.offline):
            break // state-independent
        case let .some(state):
            flags.append("≥\(state)")
        }

        if isProjected { flags.append("projected") }
        if isOffensive { flags.append("offensive") }
        if isAssistance { flags.append("assistance") }

        if !flags.isEmpty {
            text += " (\(flags.joined(separator: ", ")))"
        }
        return text
    }
}
