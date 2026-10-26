//
//  AttributeCalculator.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 18.06.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif
import DogmaModels
import BitField

/// Evaluates the flat modifier list built by `ContextBuilder`. The list is topologically
/// sorted (sources before dependents); within one target key modifiers are sorted by
/// `rawValue`, i.e. grouped by (needsStackingCheck, buffID, operation, target).
struct AttributeCalculator {
    private static let stackingPenalty: [Double] = {
        (0..<10).map { n in
            exp(-pow(Double(n), 2) / 7.1289)
        }
    }()

    /// One linear pass over the modifier list. Dead modifiers (source demoted below
    /// `minSourceState`, or target under a disallow mask) are skipped inline, so the list
    /// is never mutated between fixed-point passes.
    static func calculate(_ context: inout CalculatorContext, using sde: SDE) {
        var modifierValueBuffer: [Double] = []
        modifierValueBuffer.reserveCapacity(64)

        let mask = Modifier.$needsStackingCheck.higherBitsInclusive
        var i = context.modifiers.startIndex
        let end = context.modifiers.endIndex

        while i < end {
            let groupingID = context.modifiers[i] & mask
            let targetKey = groupingID.target
            // The aggregation rule is the same for all modifiers of a buff.
            let aggregateMin = context.modifiers[i].aggregateMin
            guard let targetAttributeInfo = sde[targetKey.attributeID]?.load() else {
                i += 1
                continue
            }
            modifierValueBuffer.removeAll(keepingCapacity: true)

            var j = i
            while j < end && (context.modifiers[j] & mask == groupingID) {
                let modifier = context.modifiers[j]
                j += 1
                guard context.isAlive(modifier) else { continue }
                guard var value = context.attributes[modifier.source] ?? (sde[modifier.source.attributeID]?.defaultValue).map({Double($0)}) else {continue}
                switch modifier.operation {
                case .addRate, .subRate:
                    let sourceEntityID = modifier.source.entityID
                    let milliseconds = context.attributes[.init(entityID: sourceEntityID, attributeID: .duration)] ??
                    context.attributes[.init(entityID: sourceEntityID, attributeID: .speed)] ?? 1000
                    value = milliseconds > 0 ? value / (milliseconds / 1000) : 0
                default:
                    value = operand(value, for: modifier.operation)
                }
                modifierValueBuffer.append(value)
            }
            i = j

            // Warfare buffs with the same ID do not add up; the strongest applies
            // (aggregateMode). Values are already converted monotonically to multipliers or
            // addends, so min/max over the buffer matches min/max over the raw values.
            if groupingID.buffID.rawValue != 0 && modifierValueBuffer.count > 1 {
                let winner = aggregateMin ? modifierValueBuffer.min()! : modifierValueBuffer.max()!
                modifierValueBuffer.removeAll(keepingCapacity: true)
                modifierValueBuffer.append(winner)
            }
            var value = context.attributes[targetKey] ?? Double(targetAttributeInfo.defaultValue)

            switch groupingID.operation {
            case .preAssignment, .postAssignment:
                value = modifierValueBuffer.last ?? value
            case .modAdd, .addRate:
                for mod in modifierValueBuffer { value += mod }
            case .modSub, .subRate:
                for mod in modifierValueBuffer { value -= mod }
            case .preDiv, .preMul, .postDiv, .postMul, .postPercent:
                if groupingID.needsStackingCheck && !targetAttributeInfo.options.contains(.isStackable) {
                    let pivot = modifierValueBuffer.partition(by: {$0 >= 1})
                    modifierValueBuffer[0..<pivot].sort(by: <)
                    modifierValueBuffer[pivot...].sort(by: >)

                    var iSP = 0
                    var n = min(pivot, Self.stackingPenalty.count)
                    for mod in modifierValueBuffer[0..<n] {
                        value *= (1 + (mod - 1) * Self.stackingPenalty[iSP])
                        iSP += 1
                    }

                    iSP = 0
                    n = min(modifierValueBuffer.count - pivot, Self.stackingPenalty.count)
                    for mod in modifierValueBuffer[pivot..<(pivot + n)] {
                        value *= (1 + (mod - 1) * Self.stackingPenalty[iSP])
                        iSP += 1
                    }
                }
                else {
                    for mod in modifierValueBuffer { value *= mod }
                }
            default: break
            }
            if targetAttributeInfo.maxAttributeID != .none {
                let maxValue = context.attributes[AttributeKey(entityID: targetKey.entityID, attributeID: targetAttributeInfo.maxAttributeID)] ?? Double(sde[targetAttributeInfo.maxAttributeID]!.defaultValue)
                value = min(value, maxValue)
            }
            if targetAttributeInfo.minAttributeID != .none {
                let minValue = context.attributes[AttributeKey(entityID: targetKey.entityID, attributeID: targetAttributeInfo.minAttributeID)] ?? Double(sde[targetAttributeInfo.minAttributeID]!.defaultValue)
                value = max(value, minValue)
            }
            context.attributes[targetKey] = value
        }
    }

    /// The value a modifier applies with, for operations that do not depend on the source's
    /// cycle time: divisions become multipliers, percentages become `1 + value / 100`.
    static func operand(_ value: Double, for operation: DogmaSDE.Modifier.Operation) -> Double {
        switch operation {
        case .preDiv, .postDiv:
            1.0 / value
        case .postPercent:
            1 + value / 100
        default:
            value
        }
    }
}
