//
// SDESchema.swift
// DogmaKit
// SDE Version: 3284752, 2026-03-31T11:27:11Z
//

import Foundation

struct _sdeInfo: Identifiable, Codable {
    var _key: String = ""
    var id: String { _key }
    var buildNumber: Int = 0
    var releaseDate: String = ""
}

struct CategoryInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var iconID: Int? = nil
    var name: NameInfo
    var published: Bool = false
}

struct GroupInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var anchorable: Bool = false
    var anchored: Bool = false
    var categoryID: Int = 0
    var fittableNonSingleton: Bool = false
    var iconID: Int? = nil
    var name: NameInfo
    var published: Bool = false
    var useBasePrice: Bool = false
}

struct TypeInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct NameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var basePrice: Double? = nil
    var capacity: Double? = nil
    var description: DescriptionInfo? = nil
    var factionID: Int? = nil
    var graphicID: Int? = nil
    var groupID: Int = 0
    var iconID: Int? = nil
    var marketGroupID: Int? = nil
    var mass: Double? = nil
    var metaGroupID: Int? = nil
    var metaLevel: Int? = nil
    var name: NameInfo
    var portionSize: Int = 0
    var published: Bool = false
    var raceID: Int? = nil
    var radius: Double? = nil
    var soundID: Int? = nil
    var variationParentTypeID: Int? = nil
    var volume: Double? = nil
}

struct TypeDogmaInfo: Identifiable, Codable {
    struct DogmaAttributesInfo: Codable {
        var attributeID: Int = 0
        var value: Double = 0
    }

    struct DogmaEffectsInfo: Codable {
        var effectID: Int = 0
        var isDefault: Bool = false
    }

    var _key: Int = 0
    var id: Int { _key }
    var dogmaAttributes: [DogmaAttributesInfo] = []
    var dogmaEffects: [DogmaEffectsInfo]? = nil
}

struct DogmaAttributeCategoryInfo: Identifiable, Codable {
    var _key: Int = 0
    var id: Int { _key }
    var description: String? = nil
    var name: String = ""
}

struct DogmaAttributeInfo: Identifiable, Codable {
    struct DisplayNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String? = nil
        var fr: String = ""
        var ja: String = ""
        var ko: String? = nil
        var ru: String = ""
        var zh: String = ""
    }

    struct TooltipDescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct TooltipTitleInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var attributeCategoryID: Int? = nil
    var chargeRechargeTimeID: Int? = nil
    var dataType: Int = 0
    var defaultValue: Double = 0
    var description: String? = nil
    var displayName: DisplayNameInfo? = nil
    var displayWhenZero: Bool = false
    var highIsGood: Bool = false
    var iconID: Int? = nil
    var maxAttributeID: Int? = nil
    var minAttributeID: Int? = nil
    var name: String = ""
    var published: Bool = false
    var stackable: Bool = false
    var tooltipDescription: TooltipDescriptionInfo? = nil
    var tooltipTitle: TooltipTitleInfo? = nil
    var unitID: Int? = nil
}

struct DogmaEffectInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct DisplayNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct ModifierInfo: Codable {
        var domain: String = ""
        var effectID: Int? = nil
        var `func`: String = ""
        var groupID: Int? = nil
        var modifiedAttributeID: Int? = nil
        var modifyingAttributeID: Int? = nil
        var operation: Int? = nil
        var skillTypeID: Int? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var disallowAutoRepeat: Bool = false
    var dischargeAttributeID: Int? = nil
    var displayName: DisplayNameInfo? = nil
    var distribution: Int? = nil
    var durationAttributeID: Int? = nil
    var effectCategoryID: Int = 0
    var electronicChance: Bool = false
    var falloffAttributeID: Int? = nil
    var fittingUsageChanceAttributeID: Int? = nil
    var guid: String? = nil
    var iconID: Int? = nil
    var isAssistance: Bool = false
    var isOffensive: Bool = false
    var isWarpSafe: Bool = false
    var modifierInfo: [ModifierInfo]? = nil
    var name: String = ""
    var npcActivationChanceAttributeID: Int? = nil
    var npcUsageChanceAttributeID: Int? = nil
    var propulsionChance: Bool = false
    var published: Bool = false
    var rangeAttributeID: Int? = nil
    var rangeChance: Bool = false
    var resistanceAttributeID: Int? = nil
    var trackingSpeedAttributeID: Int? = nil
}

struct DogmaUnitInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct DisplayNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var displayName: DisplayNameInfo? = nil
    var name: String = ""
}

struct MetaGroupInfo: Identifiable, Codable {
    struct ColorInfo: Codable {
        var b: Double = 0
        var g: Double = 0
        var r: Double = 0
    }

    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var color: ColorInfo? = nil
    var description: DescriptionInfo? = nil
    var iconID: Int? = nil
    var iconSuffix: String? = nil
    var name: NameInfo
}

struct PlanetSchematicInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct TypesInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var isInput: Bool = false
        var quantity: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var cycleTime: Int = 0
    var name: NameInfo
    var pins: [Int] = []
    var types: [TypesInfo] = []
}

struct DbuffCollectionInfo: Identifiable, Codable {
    struct DisplayNameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct ItemModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
    }

    struct LocationGroupModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
        var groupID: Int = 0
    }

    struct LocationModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
    }

    struct LocationRequiredSkillModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
        var skillID: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var aggregateMode: String = ""
    var developerDescription: String = ""
    var displayName: DisplayNameInfo? = nil
    var itemModifiers: [ItemModifiersInfo]? = nil
    var locationGroupModifiers: [LocationGroupModifiersInfo]? = nil
    var locationModifiers: [LocationModifiersInfo]? = nil
    var locationRequiredSkillModifiers: [LocationRequiredSkillModifiersInfo]? = nil
    var operationName: String = ""
    var showOutputValueInUI: String = ""
}

struct DynamicItemAttributeInfo: Identifiable, Codable {
    struct AttributeIDsInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var highIsGood: Bool? = nil
        var max: Double = 0
        var min: Double = 0
    }

    struct InputOutputMappingInfo: Codable {
        var applicableTypes: [Int] = []
        var resultingType: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var attributeIDs: [AttributeIDsInfo] = []
    var inputOutputMapping: [InputOutputMappingInfo] = []
}

struct TypeBonusInfo: Identifiable, Codable {
    struct MiscBonusesInfo: Codable {
        struct BonusTextInfo: Codable {
            var de: String = ""
            var en: String = ""
            var es: String = ""
            var fr: String = ""
            var ja: String = ""
            var ko: String = ""
            var ru: String = ""
            var zh: String = ""
        }

        var bonus: Double? = nil
        var bonusText: BonusTextInfo
        var importance: Int = 0
        var isPositive: Bool? = nil
        var unitID: Int? = nil
    }

    struct RoleBonusesInfo: Codable {
        struct BonusTextInfo: Codable {
            var de: String = ""
            var en: String = ""
            var es: String = ""
            var fr: String = ""
            var ja: String = ""
            var ko: String = ""
            var ru: String = ""
            var zh: String = ""
        }

        var bonus: Double? = nil
        var bonusText: BonusTextInfo
        var importance: Int = 0
        var unitID: Int? = nil
    }

    struct TypesInfo: Identifiable, Codable {
        struct _valueInfo: Codable {
            struct BonusTextInfo: Codable {
                var de: String? = nil
                var en: String = ""
                var es: String? = nil
                var fr: String? = nil
                var ja: String? = nil
                var ko: String? = nil
                var ru: String? = nil
                var zh: String? = nil
            }

            var bonus: Double? = nil
            var bonusText: BonusTextInfo
            var importance: Int = 0
            var unitID: Int? = nil
        }

        var _key: Int = 0
        var id: Int { _key }
        var _value: [_valueInfo] = []
    }

    var _key: Int = 0
    var id: Int { _key }
    var iconID: Int? = nil
    var miscBonuses: [MiscBonusesInfo]? = nil
    var roleBonuses: [RoleBonusesInfo]? = nil
    var types: [TypesInfo]? = nil
}
