//
//  LCGRandomNumberGenerator.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 03.07.2026.
//


struct LCGRandomNumberGenerator: RandomNumberGenerator, Sendable {
    var a: UInt64 = 2862933555777941757
    var c: UInt64 = 3037000493
    var m: UInt64 = 1<<64
    var seed: UInt64 = 1
    
    public mutating func next() -> UInt64 {
        let r = a &* seed &+ c
        seed = m > 0 ? (r % m) : r
        return seed
    }
}
