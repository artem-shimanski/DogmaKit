//
//  PerfectMultiplier.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 03.07.2026.
//

extension FixedWidthInteger {
    @inlinable
    var nextPowerOfTwo: Self {
        1 << (Self.bitWidth - (self - 1).leadingZeroBitCount)
    }
}


func build<C: Collection, Key: FixedWidthInteger> (
    for collection: C,
    by keyForElement: (C.Element) -> Key
) -> (multipliers: [Key], sparseTable: [UInt16]) where C.Index == Int {
    let count = collection.count
    guard count > 0 else {return ([], [])}
    // `UInt16.max` marks an empty cell during construction.
    precondition(count < Int(UInt16.max), "PerfectDictionary: \(count) entries do not fit into UInt16 indices")
    var rng = LCGRandomNumberGenerator(seed: 1)
    var bufferSize = count.nextPowerOfTwo
    for _ in 0..<2 {
        var bucketCount = max(bufferSize / 8, 1)
        for _ in 0..<3 {
            let mask = Key(bufferSize - 1)
            let shift = MemoryLayout<Key>.size * 8 - bufferSize.trailingZeroBitCount
            
            var buckets: [[Int]] = .init(repeating: [], count: bucketCount)
            let bucketMask = Key(bucketCount - 1)
            
            
            for (i, element) in collection.enumerated() {
                let idx = Int(keyForElement(element) & bucketMask)
                buckets[idx].append(i)
            }
            
            let order = (0..<bucketCount).sorted { buckets[$0].count > buckets[$1].count }
            
            var sparseTable = [UInt16](repeating: .max, count: bufferSize)
            var multipliers = [Key](repeating: 0, count: bucketCount)
            
            // Failing ANY bucket fails the whole layout: its keys would not be in the table and would look up as `nil`.
            var success = true
            for bucketIdx in order where success {
                var magicNumber: Key = 1
                for _ in 0..<2000 {
                    success = true
                    magicNumber = Key.random(in: 0...Key.max, using: &rng) | 1
                    var temporaryIndices = [Key]()
                    let bucket = buckets[bucketIdx]
                    
                    for i in bucket {
                        let key = keyForElement(collection[i])
                        let idx = ((key &* magicNumber) >> shift) & mask
                        
                        if sparseTable[Int(idx)] != .max || temporaryIndices.contains(idx) {
                            success = false
                            break
                        }
                        temporaryIndices.append(idx)
                    }
                    
                    if success {
                        for (i, denseIdx) in bucket.enumerated() {
                            let idx = temporaryIndices[i]
                            sparseTable[Int(idx)] = UInt16(denseIdx)
                        }
                        multipliers[bucketIdx] = magicNumber
                        break
                    }
                }
            }
            if success {
                for (i, element) in collection.enumerated() {
                    let key = keyForElement(element)
                    let idx = ((key &* multipliers[Int(key & bucketMask)]) >> shift) & mask
                    precondition(sparseTable[Int(idx)] == UInt16(i), "PerfectDictionary: key \(key) cannot be found")
                }
                return (multipliers, sparseTable.map{$0 == .max ? 0 : $0})
            }
            bucketCount *= 2
        }
        bufferSize *= 2
    }
    fatalError()
}
