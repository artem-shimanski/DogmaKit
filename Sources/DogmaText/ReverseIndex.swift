//
//  ReverseIndex.swift
//  DogmaText
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Synchronization
import DogmaModels

/// Lazy reverse-index cache. A reference type so copies of `TextCatalog` share one built dictionary.
final class ReverseIndex: Sendable {

    struct Tables: Sendable {
        var types: [String: TypeID] = [:]
        var attributes: [String: AttributeID] = [:]
    }

    private let storage = Mutex<Tables?>(nil)

    init() {}

    /// Built under a lock: building is idempotent, but doing it twice in parallel wastes time and memory.
    func tables(_ build: () -> Tables) -> Tables {
        storage.withLock { storage in
            if let storage { return storage }
            let tables = build()
            storage = tables
            return tables
        }
    }
}
