//
//  SDEFile.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 26.10.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
import DogmaKitResources
#endif

/// `sde.bin`: from the `DogmaKitResources` bundle, or on WebAssembly from next to the executable.
enum SDEFile {
    static var url: URL? {
        #if os(WASI)
        executableDirectory.appending(path: "sde.bin")
        #else
        DogmaKitResources.sde
        #endif
    }

    static func load() throws -> Data {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}
