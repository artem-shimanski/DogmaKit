//
//  Target.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 08.07.2026.
//

import Foundation

public struct Target: Sendable, Equatable {
    public var angularVelocity: Double
    public var velocity: Double
    public var signature: Double
    public var range: Double
    
    public static let zero: Target = .init(angularVelocity: 0, velocity: 0, signature: 0, range: 0)
    
    public init(angularVelocity: Double, velocity: Double, signature: Double, range: Double) {
        self.angularVelocity = angularVelocity
        self.velocity = velocity
        self.signature = signature
        self.range = range
    }
}
