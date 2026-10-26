//
//  DogmaKitResources.swift
//  DogmaKitResources
//
//  Created by Artem Shimanski on 26.10.2026.
//

import Foundation

/// `sde.bin`, the engine's database. A target of its own: the resource accessor SwiftPM generates for `Bundle`
/// imports full Foundation, which platforms without `Bundle` (WebAssembly) leave out.
package enum DogmaKitResources {
    package static var sde: URL? {
        Bundle.module.url(forResource: "sde", withExtension: "bin")
    }
}
