//
//  DogmaSDE+Extensions.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 26.04.2026.
//

import Foundation

extension DogmaSDE.AttributeInfo {
    @MainActor
    init(_ info: DogmaAttributeInfo) {
        var options: DogmaSDE.AttributeOptions = []
        if info.highIsGood {
            options.insert(.highIsGood)
        }
        if info.stackable {
            options.insert(.isStackable)
        }
        self.init(id: .init(rawValue: UInt16(info._key)),
                  category: .init(rawValue: UInt16(info.attributeCategoryID ?? 0)),
                  minAttributeID: .init(rawValue: UInt16(info.minAttributeID ?? 0)),
                  maxAttributeID: .init(rawValue: UInt16(info.maxAttributeID ?? 0)),
                  defaultValue: Float(info.defaultValue),
                  unit: .init(rawValue: UInt16(info.unitID ?? 0)),
                  options: options)
    }
}

extension DogmaSDE.TypeInfo {

    @MainActor
    init(_ info: TypeInfo) {
        let typeDogma = typesDogma[info._key]
        let pairs = typeDogma?.dogmaAttributes.map {(AttributeID(rawValue: UInt16($0.attributeID)), Float($0.value))} ?? []
        var attributes = Dictionary(uniqueKeysWithValues: pairs)
        
        func update(_ attributeName: String, value: Double?) {
            guard let value, value > 0 else {return}
            let id = dogmaAttributes.index(of: attributeName)!
            attributes[id] = Float(value)
        }
        update("radius", value: info.radius)
        update("mass", value: info.mass)
        update("volume", value: info.volume)
        update("capacity", value: info.capacity)
        update("raceID", value: info.raceID.map{Double($0)})
        
        let categoryID = CategoryID(rawValue: UInt16(groups[info.groupID]!.categoryID))
        
        let effectIDs = typeDogma?.dogmaEffects?.map{EffectID(rawValue: UInt16($0.effectID))}
        let effects = effectIDs?.map{dogmaEffects[$0]!}
        
        // Ordered by attributeID (requiredSkill1, 2, 3...); dictionary order is random.
        let requiredSkills = attributes.filter{requiredSkillsAttributeIDs.contains($0.key)}
            .sorted{$0.key < $1.key}
            .map{TypeID(rawValue: UInt32($0.value))}
        
        self.init(id: .init(rawValue: UInt32(info._key)),
                  groupID: .init(rawValue: UInt16(info.groupID)),
                  categoryID: categoryID,
                  metaGroup: .init(rawValue: UInt16(info.metaGroupID ?? 0)),
                  metaLevel: Int32(info.metaLevel ?? -1),
                  attributes: PerfectDictionary(attributes),
                  effects: effects ?? [],
                  requiredSkills: requiredSkills,
                  fittingRequirements: FittingRequirements(attributes),
                  chargeRequirements: ChargeRequirements(attributes)
        )
    }
}

extension DogmaSDE.TypeInfo.FittingRequirements {
    init?(_ attributes: [AttributeID: Float]) {
        
        let canFitShipType = attributes.filter{canFitShipTypeAttributesIDs.contains($0.key)}
            .map{TypeID(rawValue: UInt32($0.value))}
        let canFitShipGroup = attributes.filter{canFitShipGroupAttributesIDs.contains($0.key)}
            .map{GroupID(rawValue: UInt16($0.value))}
        
        guard !canFitShipGroup.isEmpty || !canFitShipType.isEmpty else {return nil}
        self.init(canFitShipGroup: canFitShipGroup.sorted{$0.rawValue < $1.rawValue}, canFitShipType: canFitShipType.sorted{$0.rawValue < $1.rawValue})
    }
}

extension DogmaSDE.TypeInfo.ChargeRequirements {
    init?(_ attributes: [AttributeID: Float]) {
        let chargeGroup = attributes.filter{chargeGroupAttributesIDs.contains($0.key)}
            .sorted{$0.key < $1.key}
            .map{GroupID(rawValue: UInt16($0.value))}
        let chargeSize = attributes[chargeSizeID].map{UInt8(exactly: $0)!} ?? 0
        guard !chargeGroup.isEmpty else {return nil}

        self.init(chargeGroup: chargeGroup, chargeSize: chargeSize)
    }
}

extension DogmaSDE.Effect {
    init(_ info: DogmaEffectInfo) {
        var options: DogmaSDE.EffectOptions = []
        if info.isAssistance { options.insert(.isAssistance) }
        if info.isOffensive { options.insert(.isOffensive) }
        self.init(id: .init(rawValue: UInt16(info._key)),
                  category: Category(rawValue: UInt8(1 << info.effectCategoryID)),
                  modifiers: info.modifierInfo?.compactMap{.init($0)} ?? [],
                  options: options)
    }
}

extension DogmaSDE.Modifier.Operation {
    init(_ value: Int) {
        switch value {
        case -1:
            self = .preAssignment
        case 0:
            self = .preMul
        case 2:
            self = .modAdd
        case 3:
            self = .modSub
        case 4:
            self = .postMul
        case 5:
            self = .postDiv
        case 6:
            self = .postPercent
        case 7:
            self = .postAssignment
        case 9:
            self = .skillTime
        default:
            fatalError("Unknown modifier operation: \(sde)")
        }
    }
}

extension DogmaSDE.Modifier.Operation {
    /// `operationName` from dbuffCollections.jsonl (text names instead of numeric codes).
    init(name: String) {
        switch name {
        case "PreAssignment":
            self = .preAssignment
        case "PreMul":
            self = .preMul
        case "PreDiv":
            self = .preDiv
        case "ModAdd":
            self = .modAdd
        case "ModSub":
            self = .modSub
        case "PostMul":
            self = .postMul
        case "PostDiv":
            self = .postDiv
        case "PostPercent":
            self = .postPercent
        case "PostAssignment":
            self = .postAssignment
        case "SkillTime":
            self = .skillTime
        default:
            fatalError("Unknown buff operation: \(name)")
        }
    }
}

extension DogmaSDE.WarfareBuff.AggregateMode {
    init(name: String) {
        switch name {
        case "Maximum":
            self = .maximum
        case "Minimum":
            self = .minimum
        default:
            fatalError("Unknown buff aggregate mode: \(name)")
        }
    }
}

extension DogmaSDE.WarfareBuff.Visibility {
    init(name: String) {
        switch name {
        case "ShowNormal":
            self = .normal
        case "ShowInverted":
            self = .inverted
        case "Hide":
            self = .hidden
        default:
            fatalError("Unknown buff visibility: \(name)")
        }
    }
}

extension DbuffCollectionInfo {
    /// Name used to generate the `WarfareBuffID` constant. `developerDescription` is more unique than `displayName`.
    var buffName: String {
        for candidate in [developerDescription, displayName?.en ?? ""] {
            let name = candidate.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return "warfareBuff\(_key)"
    }
}

extension DogmaSDE.WarfareBuff {
    /// Imports a dbuff collection. Every modifier gets the collection's operation, the `.gang` domain and an empty
    /// `modifyingAttributeID`; the engine supplies the magnitude from the source's `warfareBuff{N}Value`.
    @MainActor
    init(_ info: DbuffCollectionInfo) {
        let operation = DogmaSDE.Modifier.Operation(name: info.operationName)
        var modifiers: [DogmaSDE.Modifier] = []

        func append(_ scope: DogmaSDE.Modifier.Scope, _ attributeID: Int) {
            let modifiedAttributeID = AttributeID(rawValue: UInt16(attributeID))
            guard dogmaAttributes[modifiedAttributeID] != nil else {
                print("warning: buff \(info._key) skipped: unknown attribute \(attributeID)")
                return
            }
            modifiers.append(DogmaSDE.Modifier(scope: scope,
                                               operation: operation,
                                               domain: .gang,
                                               modifiedAttributeID: modifiedAttributeID,
                                               modifyingAttributeID: .init(rawValue: 0)))
        }

        for modifier in info.itemModifiers ?? [] {
            append(.item, modifier.dogmaAttributeID)
        }
        for modifier in info.locationModifiers ?? [] {
            append(.location, modifier.dogmaAttributeID)
        }
        for modifier in info.locationGroupModifiers ?? [] {
            guard groups[modifier.groupID] != nil else {
                print("warning: buff \(info._key) skipped: unknown group \(modifier.groupID)")
                continue
            }
            append(.locationGroup(.init(rawValue: UInt16(modifier.groupID))), modifier.dogmaAttributeID)
        }
        for modifier in info.locationRequiredSkillModifiers ?? [] {
            let skillID = TypeID(rawValue: UInt32(modifier.skillID))
            guard types[skillID] != nil else {
                print("warning: buff \(info._key) skipped: unknown skill \(modifier.skillID)")
                continue
            }
            append(.locationRequiredSkill(skillID), modifier.dogmaAttributeID)
        }

        self.init(id: .init(rawValue: UInt16(info._key)),
                  info: .init(operation: operation,
                              aggregateMode: .init(name: info.aggregateMode),
                              visibility: .init(name: info.showOutputValueInUI)),
                  modifiers: modifiers)
    }
}

extension DogmaSDE.Mutaplasmid {
    init(_ info: DynamicItemAttributeInfo, filteredTypeIDs: Set<TypeID>) {
        let ranges = info.attributeIDs.map { attribute in
            Range(id: AttributeID(rawValue: UInt16(attribute.id)),
                  min: Float(attribute.min),
                  max: Float(attribute.max),
                  highIsGood: attribute.highIsGood.map{$0 ? .forcedTrue : .forcedFalse} ?? .inherited)
        }.sorted{$0.id.rawValue < $1.id.rawValue}
        precondition(info.inputOutputMapping.count == 1)
        let applicableTypes = Set(info.inputOutputMapping[0].applicableTypes.map{TypeID(rawValue: UInt32($0))})
            .intersection(filteredTypeIDs)
        precondition(!applicableTypes.isEmpty)
        self.init(id: TypeID(rawValue: UInt32(info.id)),
                  resultingTypeID: TypeID(rawValue: UInt32(info.inputOutputMapping[0].resultingType)), applicableTypes: PerfectSet(applicableTypes), ranges: ranges)
    }
}

extension DogmaSDE.Modifier.Domain {
    init(_ value: String) {
        switch value {
        case "charID":
            self = .pilot
        case "itemID":
            self = .`self`
        case "otherID":
            self = .other
        case "shipID", "structureID":
            self = .hull
        case "target", "targetID":
            self = .target
        default:
            fatalError("Unknown modifier domain: \(sde)")
        }
    }
}

extension DogmaSDE.Modifier {
    init?(_ value: DogmaEffectInfo.ModifierInfo) {
        let scope: DogmaSDE.Modifier.Scope
        switch value.func {
        case "LocationModifier":
            scope = .location
        case "ItemModifier":
            scope = .item
        case "LocationGroupModifier":
            scope = .locationGroup(.init(rawValue: UInt16(value.groupID!)))
        case "OwnerRequiredSkillModifier":
            scope = .ownerRequiredSkill(.init(rawValue: UInt32(value.skillTypeID!)))
        case "LocationRequiredSkillModifier":
            scope = .locationRequiredSkill(.init(rawValue: UInt32(value.skillTypeID!)))
        case "EffectStopper":
            return nil
        default:
            fatalError()
        }
        
        self.init(scope: scope,
                  operation: value.operation.map{.init($0)} ?? .none,
                  domain: .init(value.domain),
                  modifiedAttributeID: .init(rawValue: UInt16(value.modifiedAttributeID ?? 0)),
                  modifyingAttributeID: .init(rawValue: UInt16(value.modifyingAttributeID ?? 0)))
    }
    
    @MainActor
    static func item(_ domain: DogmaSDE.Modifier.Domain, _ modifiedAttribute: String, _ operation: DogmaSDE.Modifier.Operation, _ modifyingAttribute: String) -> DogmaSDE.Modifier {
        DogmaSDE.Modifier(scope: .item, operation: operation, domain: domain, modifiedAttributeID: dogmaAttributes.index(of: modifiedAttribute)!, modifyingAttributeID: dogmaAttributes.index(of: modifyingAttribute)!)
    }
    
    @MainActor
    static func locationGroup(_ domain: DogmaSDE.Modifier.Domain, _ group: String, _ modifiedAttribute: String, _ operation: DogmaSDE.Modifier.Operation, _ modifyingAttribute: String) -> DogmaSDE.Modifier {
        DogmaSDE.Modifier(scope: .locationGroup(.init(rawValue: UInt16(groups.nameToID[group]!))), operation: operation, domain: domain, modifiedAttributeID: dogmaAttributes.index(of: modifiedAttribute)!, modifyingAttributeID: dogmaAttributes.index(of: modifyingAttribute)!)
    }
    
    @MainActor
    static func locationRequiredSkill(_ domain: DogmaSDE.Modifier.Domain, _ skill: String, _ modifiedAttribute: String, _ operation: DogmaSDE.Modifier.Operation, _ modifyingAttribute: String) -> DogmaSDE.Modifier {
        DogmaSDE.Modifier(scope: .locationRequiredSkill(types.nameToID[skill]!), operation: operation, domain: domain, modifiedAttributeID: dogmaAttributes.index(of: modifiedAttribute)!, modifyingAttributeID: dogmaAttributes.index(of: modifyingAttribute)!)
    }
    
    @MainActor
    static func ownerRequiredSkill(_ domain: DogmaSDE.Modifier.Domain, _ skill: String, _ modifiedAttribute: String, _ operation: DogmaSDE.Modifier.Operation, _ modifyingAttribute: String) -> DogmaSDE.Modifier {
        DogmaSDE.Modifier(scope: .ownerRequiredSkill(types.nameToID[skill]!), operation: operation, domain: domain, modifiedAttributeID: dogmaAttributes.index(of: modifiedAttribute)!, modifyingAttributeID: dogmaAttributes.index(of: modifyingAttribute)!)
    }

    @MainActor
    static func locationRequiredDomainSkill(_ domain: DogmaSDE.Modifier.Domain, _ modifiedAttribute: String, _ operation: DogmaSDE.Modifier.Operation, _ modifyingAttribute: String, _ targetDomain: DogmaSDE.Modifier.Domain) -> DogmaSDE.Modifier {
        DogmaSDE.Modifier(scope: .locationRequiredDomainSkill(targetDomain), operation: operation, domain: domain, modifiedAttributeID: dogmaAttributes.index(of: modifiedAttribute)!, modifyingAttributeID: dogmaAttributes.index(of: modifyingAttribute)!)
    }
}

