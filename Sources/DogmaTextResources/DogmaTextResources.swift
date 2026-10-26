//
//  DogmaTextResources.swift
//  DogmaTextResources
//
//  Created by Artem Shimanski on 26.10.2026.
//

import Foundation

/// `text-en.bin`, the English name catalog. A target of its own for the same reason as `DogmaKitResources`.
package enum DogmaTextResources {
    package static var english: URL? {
        Bundle.module.url(forResource: "text-en", withExtension: "bin")
    }
}
