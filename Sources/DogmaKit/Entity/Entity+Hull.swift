//
//  Entity+Hull.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

/// Rig size (the `rigSize` attribute). Present on both hulls (which rigs they accept) and
/// rigs; they must match. Structures use the same values.
public enum RigSize: UInt8, BitwiseCopyable, Sendable, CaseIterable {
    /// Attribute missing or zero (shuttles, capsules, rigs without a size).
    case none = 0
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
}

extension RigSize {
    /// Parses a raw `rigSize` value. Unknown values map to `.none`; the compatibility check
    /// compares raw values so that unknown sizes do not match hulls without a rig size.
    @inlinable
    public init(_ rawAttributeValue: Double) {
        self = UInt8(exactly: rawAttributeValue.rounded()).flatMap(RigSize.init(rawValue:)) ?? .none
    }
}
