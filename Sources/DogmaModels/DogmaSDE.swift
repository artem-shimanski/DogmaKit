//
//  DogmaDomain.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 10.04.2026.
//

import Foundation
import FlatBin

@FlatCodable
public struct DogmaSDE: Sendable {
    
    @FlatRawCodable
    public struct AttributeOptions: OptionSet, BitwiseCopyable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        public static let isStackable = AttributeOptions(rawValue: 1 << 0)
        public static let highIsGood = AttributeOptions(rawValue: 1 << 1)
    }
    
    @FlatRawCodable
    public struct EffectOptions: OptionSet, BitwiseCopyable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        public static let isOffensive = EffectOptions(rawValue: 1 << 0)
        public static let isAssistance = EffectOptions(rawValue: 1 << 1)
        public static let isWarpSafe = EffectOptions(rawValue: 1 << 2)
    }
    
    public typealias CubicMeter = Float
    public typealias MetaLevel = Int32
    
    @FlatCodable
    public struct AttributeInfo: Identifiable, BitwiseCopyable, Sendable {
        public var id: AttributeID
        public var category: AttributeCategoryID
        public var defaultValue: Float
        public var minAttributeID: AttributeID
        public var maxAttributeID: AttributeID
        public var unit: UnitID
        public var options: AttributeOptions
        
        public init(id: AttributeID, category: AttributeCategoryID, minAttributeID: AttributeID, maxAttributeID: AttributeID, defaultValue: Float, unit: UnitID, options: AttributeOptions) {
            self.id = id
            self.category = category
            self.minAttributeID = minAttributeID
            self.maxAttributeID = maxAttributeID
            self.defaultValue = defaultValue
            self.unit = unit
            self.options = options
        }
    }
    
    @FlatRawCodable
    public struct Modifier: BitwiseCopyable, Sendable {
        
        public enum Scope: BitwiseCopyable, Sendable {
            case item
            case location
            case locationGroup (GroupID)
            case locationRequiredSkill (TypeID)
            case ownerRequiredSkill (TypeID)
            case locationRequiredDomainSkill (Domain)
        }
        
        public enum Operation: UInt8, BitwiseCopyable, Sendable {
            case none
            case preAssignment
            case modAdd
            case modSub
            case addRate
            case subRate
            case preDiv
            case preMul
            case postAssignment
            case postDiv
            case postMul
            case postPercent
            case skillTime
        }
        
        public enum Domain: UInt8, BitwiseCopyable, Sendable {
            case `self`
            case pilot
            case hull
            case gang
            case environment
            case target
            case other
        }
        
        public var scope: Scope
        public var operation: Operation
        public var domain: Domain
        /// Explicit zero byte in place of alignment padding before `modifiedAttributeID`. `@FlatRawCodable` copies the
        /// struct including padding, and implicit padding holds garbage, which would make `sde.bin` differ between runs.
        private var padding: UInt8 = 0
        public var modifiedAttributeID: AttributeID
        public var modifyingAttributeID: AttributeID
        
        public init(scope: Scope, operation: Operation, domain: Domain, modifiedAttributeID: AttributeID, modifyingAttributeID: AttributeID) {
            self.scope = scope
            self.operation = operation
            self.domain = domain
            self.modifiedAttributeID = modifiedAttributeID
            self.modifyingAttributeID = modifyingAttributeID
        }
    }
    
    @FlatCodable
    public struct Effect: Identifiable, Sendable {
        @FlatRawCodable
        public struct Category: OptionSet, Sendable {
            public var rawValue: UInt8
            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            public static let passive = Category(rawValue: 1 << 0)
            public static let activation = Category(rawValue: 1 << 1)
            public static let target = Category(rawValue: 1 << 2)
            public static let environment = Category(rawValue: 1 << 3)
            public static let online = Category(rawValue: 1 << 4)
            public static let overload = Category(rawValue: 1 << 5)
            public static let dungeon = Category(rawValue: 1 << 6)
            public static let system = Category(rawValue: 1 << 7)
        }
        
        public var id: EffectID
        public var category: Category
        public var modifiers: [Modifier]
        public var options: EffectOptions
        
        public init(id: EffectID, category: Category, modifiers: [Modifier] = [], options: EffectOptions = []) {
            self.id = id
            self.category = category
            self.modifiers = modifiers
            self.options = options
        }
    }
    
    /// Warfare buff (dbuff): modifiers that a source (Command Burst with a charge, Phenomena Generator,
    /// environment effect) distributes to the fleet. Imported from `dbuffCollections.jsonl`.
    ///
    /// The magnitude is not stored in the modifiers (`Modifier.modifyingAttributeID` == 0, `Modifier.domain` == `.gang`):
    /// the engine uses the source entity's `warfareBuff{1...4}Value`.
    @FlatCodable
    public struct WarfareBuff: Identifiable, Sendable {

        /// How several identical buffs (same `WarfareBuffID`) on one target aggregate: the strongest applies.
        /// `maximum` for bonuses, `minimum` where lower is better (resistances, durations, signature).
        public enum AggregateMode: UInt8, BitwiseCopyable, Sendable {
            case maximum
            case minimum
        }

        /// How the buff magnitude is shown in UI (`showOutputValueInUI` in the SDE).
        public enum Visibility: UInt8, BitwiseCopyable, Sendable {
            /// As is.
            case normal
            /// Sign flipped: stored as -8% to resonance, shown to the user as +8% resistance.
            case inverted
            /// Service buff, not shown in UI.
            case hidden
        }

        /// Scalar part of the buff, a separate POD so it fits `@FlatRawCodable`.
        @FlatRawCodable
        public struct Info: BitwiseCopyable, Sendable {
            /// Operation used to apply the buff magnitude to the target. Duplicated in each modifier, but also needed
            /// here: it defines the neutral element for aggregation (0 for `modAdd`/`postPercent`, 1 for `postMul`).
            public var operation: Modifier.Operation
            public var aggregateMode: AggregateMode
            public var visibility: Visibility

            public init(operation: Modifier.Operation, aggregateMode: AggregateMode, visibility: Visibility) {
                self.operation = operation
                self.aggregateMode = aggregateMode
                self.visibility = visibility
            }
        }

        public var id: WarfareBuffID
        public var info: Info
        public var modifiers: [Modifier]

        public init(id: WarfareBuffID,
                    info: Info = .init(operation: .postPercent, aggregateMode: .maximum, visibility: .normal),
                    modifiers: [Modifier]) {
            self.id = id
            self.info = info
            self.modifiers = modifiers
        }
    }
    
    @FlatCodable
    public struct TypeInfo: Identifiable, Sendable {
        @FlatRawCodable
        public struct Attribute: BitwiseCopyable, Identifiable, Sendable {
            public var id: AttributeID
            public var value: Float
            public init(id: AttributeID, value: Float) {
                self.id = id
                self.value = value
            }
        }
        
        @FlatCodable
        public struct FittingRequirements: Sendable {
            public var canFitShipGroup: [GroupID]
            public var canFitShipType: [TypeID]
            
            public init(canFitShipGroup: [GroupID], canFitShipType: [TypeID]) {
                self.canFitShipGroup = canFitShipGroup
                self.canFitShipType = canFitShipType
            }
        }
        
        @FlatCodable
        public struct ChargeRequirements: Sendable {
            public var chargeGroup: [GroupID]
            public var chargeSize: UInt8

            public init(chargeGroup: [GroupID], chargeSize: UInt8) {
                self.chargeGroup = chargeGroup
                self.chargeSize = chargeSize
            }
        }
        
        public var id: TypeID
        public var groupID: GroupID
        public var categoryID: CategoryID
        public var metaGroup: MetaGroupID
        public var metaLevel: MetaLevel
        public var attributes: PerfectDictionary<AttributeID, Float>
        @FlatShared
        public var effects: [Effect]
        public var requiredSkills: [TypeID]
        public var fittingRequirements: FittingRequirements?
        public var chargeRequirements: ChargeRequirements?
        
        public init(id: TypeID, groupID: GroupID, categoryID: CategoryID, metaGroup: MetaGroupID, metaLevel: MetaLevel, attributes: PerfectDictionary<AttributeID, Float>, effects: [Effect], requiredSkills: [TypeID], fittingRequirements: FittingRequirements?, chargeRequirements: ChargeRequirements?) {
            self.id = id
            self.groupID = groupID
            self.categoryID = categoryID
            self.metaGroup = metaGroup
            self.metaLevel = metaLevel
            self.attributes = attributes
            self.effects = effects
            self.requiredSkills = requiredSkills
            self.fittingRequirements = fittingRequirements
            self.chargeRequirements = chargeRequirements
        }
    }
    
    @FlatCodable
    public struct Mutaplasmid: Identifiable, Sendable {
        @FlatRawCodable
        public struct Range: BitwiseCopyable, Identifiable, Sendable {
            @FlatRawCodable
            public enum HighIsGood: Sendable {
                case inherited
                case forcedTrue
                case forcedFalse
                
                @inlinable
                public var asBool: Bool? {
                    switch self {
                    case .inherited: nil
                    case .forcedTrue: true
                    case .forcedFalse: false
                    }
                }
            }

            public var id: AttributeID      // mutated attribute
            private var padding0: UInt16 = 0 // explicit padding, see `Modifier.padding`
            public var min: Float           // multipliers of the base value
            public var max: Float
            public var highIsGood: HighIsGood
            private var padding1: UInt8 = 0
            private var padding2: UInt16 = 0
            
            public init(id: AttributeID, min: Float, max: Float, highIsGood: HighIsGood) {
                self.id = id
                self.min = min
                self.max = max
                self.highIsGood = highIsGood
            }
        }
        public var id: TypeID               // mutaplasmid type ID
        public var resultingTypeID: TypeID
        public var applicableTypes: PerfectSet<TypeID>
        public var ranges: [Range]             // sorted by attributeID
        
        public init(id: TypeID, resultingTypeID: TypeID, applicableTypes: PerfectSet<TypeID>, ranges: [Range]) {
            self.id = id
            self.resultingTypeID = resultingTypeID
            self.applicableTypes = applicableTypes
            self.ranges = ranges
        }
    }
    
    public var types: PerfectDictionary<TypeID, TypeInfo> = [:]
    public var attributes: PerfectDictionary<AttributeID, AttributeInfo> = [:]
    public var warfareBuffs: PerfectDictionary<WarfareBuffID, WarfareBuff> = [:]
    public var skills: [TypeID] = []
    public var mutaplasmids: PerfectDictionary<TypeID, Mutaplasmid> = [:]
    
    public init() {}
    
    public init(contentsOf data: Data) {
        let decoder = FlatDecoder(data: data)
        self = decoder.decode(Self.self).load()
    }
}
