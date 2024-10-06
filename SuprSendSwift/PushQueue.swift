//
//  PushQueue.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 03/10/24.
//

import Foundation

class PushQueue {
    
    private let userDefaultsKey: String = "PushQueueItems"
    
    let config: SuprSend
    
    init(config: SuprSend) {
        self.config = config
        items = UserDefaultsManager.shared.get() ?? []
        
        flush()
    }
    
    private var items: [PushQueueItem] {
        didSet {
            UserDefaultsManager.shared.set(items)
        }
    }
    
    func push(_ item: PushQueueItem) {
        items.append(item)
        flush()
    }
    
    private func flush() {
        while let item = pop() {
            Task {
                let response = await triggetEvent(item: item)
                
                if response.status == .error {
                    pushOnly(item)
                }
            }
        }
    }
    
    
    private func pushOnly(_ item: PushQueueItem) {
        items.append(item)
    }
    
    private func pop() -> PushQueueItem? {
        if items.isEmpty {
            return nil
        }
        return items.removeFirst()
    }
    
    private func triggetEvent(item: PushQueueItem) async -> APIResponse {
        await config.trackPublic(event: item.event, properties: [
            "id": item.nid
        ])
    }
}

struct PushQueueItem: Codable {
    let event: String
    let nid: String
}

class UserDefaultsManager {
    
    static let shared = UserDefaultsManager()
    
    private let userDefaultsKey: String = "PushQueueItems"
    
    func set(_ value: [PushQueueItem]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(value) {
            let defaults = UserDefaults.standard
            defaults.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func get() -> [PushQueueItem]? {
        if let savedPerson = UserDefaults.standard.object(forKey: userDefaultsKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedPerson = try? decoder.decode([PushQueueItem].self, from: savedPerson) {
                return loadedPerson
            }
        }
        return nil
    }
}
