//
//  FitStats+Snapshot.swift
//  DogmaKit
//

// Collections snapshot into arrays of their elements' snapshots. `Snapshot` aliases let
// `@SnapshotNested` name the field type as `Collection.Snapshot`.

extension FitStats.Pilots {
    public typealias Snapshot = [FitStats.Pilot.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Modules {
    public typealias Snapshot = [FitStats.Module.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Drones {
    public typealias Snapshot = [FitStats.Drone.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Skills {
    public typealias Snapshot = [FitStats.Skill.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Implants {
    public typealias Snapshot = [FitStats.Implant.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Boosters {
    public typealias Snapshot = [FitStats.Booster.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}

extension FitStats.Environment {
    public typealias Snapshot = [FitStats.EnvironmentEffect.Snapshot]

    public func snapshot() -> Snapshot {
        var result: Snapshot = []
        forEach { result.append($0.snapshot()) }
        return result
    }
}
