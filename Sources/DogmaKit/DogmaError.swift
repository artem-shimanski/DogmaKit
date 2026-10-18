//
//  DogmaError.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 23.06.2026.
//

public enum DogmaError: Error, Sendable {
    case typeNotFound(TypeID)
    case invalidCategory(CategoryID, expected: Set<CategoryID>)
    case cantFit(TypeID, to: TypeID)
    case typeLimitExceeded(TypeID)
    case groupLimitExceeded(GroupID)
    case entityLimitExceeded
    /// There are already `Fit.Pilots.maxCount` pilots; no more fit in `EntityID.pilotID`.
    case pilotLimitExceeded

    /// The rig size does not match the hull's (`rigSize` attribute).
    case rigSizeMismatch(TypeID, expected: RigSize, actual: RigSize)
    /// The subsystem slot (`subSystemSlot`) is already taken; `by` is the fitted subsystem's type.
    case subsystemSlotOccupied(TypeID, by: TypeID)
    /// The hull does not support subsystems (no `maxSubSystems`).
    case subsystemsNotSupported(by: TypeID)

    /// No mutaplasmid with this type ID in the SDE.
    case mutaplasmidNotFound(TypeID)
    /// The mutaplasmid does not apply to this base type (not in `applicableTypes`).
    case mutaplasmidNotApplicable(TypeID, to: TypeID)
    /// The attribute is not within the mutaplasmid's ranges.
    case attributeNotMutable(AttributeID, by: TypeID)
    /// The operation applies only to a mutated (abyssal) entity.
    case notMutated(EntityID)
    
    case implantSlotOccupied(TypeID, by: TypeID)
    case boosterSlotOccupied(TypeID, by: TypeID)
    case attributeNotFound(AttributeID)
}
