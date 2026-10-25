//
//  Snapshottable.swift
//  DogmaKit
//

// Snapshots copy values out of the engine and never hold its buffers: the engine reuses
// them in place, and a retained reference would force a copy on the next recalculation.
// Every `FitStats` node and collection can be snapshotted, so a reader copies only the
// part it needs. Formulas live in value types (`Weapon`, `Armament`, `TankProfile`,
// simulators) that nodes return and snapshots store, so no math is duplicated.

/// Generates `Snapshot` (one `public let` per field) and `snapshot()` for a `FitStats`
/// node. Fields: every `public` instance property, unless `@SnapshotIgnored`, plus
/// parameterless methods marked `@SnapshotField`. A property whose type cannot be stored
/// in a `Sendable` value (a `~Escapable` view) fails to compile until it is marked.
@attached(member, names: named(Snapshot), named(snapshot))
macro Snapshottable() = #externalMacro(module: "DogmaKitMacros", type: "SnapshottableMacro")

/// Excludes a property from the snapshot.
@attached(peer)
macro SnapshotIgnored() = #externalMacro(module: "DogmaKitMacros", type: "SnapshotMarkerMacro")

/// Includes a parameterless method in the snapshot under its own name.
@attached(peer)
macro SnapshotField() = #externalMacro(module: "DogmaKitMacros", type: "SnapshotMarkerMacro")

/// A property or method returning another node or collection: stored as its `Snapshot`.
@attached(peer)
macro SnapshotNested() = #externalMacro(module: "DogmaKitMacros", type: "SnapshotMarkerMacro")
