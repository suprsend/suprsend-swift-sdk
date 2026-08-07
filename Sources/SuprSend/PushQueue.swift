//
//  PushQueue.swift
//  SuprSend
//
//  Created by Ram Suthar on 03/10/24.
//

import Foundation

class PushQueue {
    
    private let userDefaultsKey: String = "PushQueueItems"
    
    let config: SuprSendClient

    //declare this property where it won't go out of scope relative to your listener
    let reachability = try! Reachability()

    // Serializes all access to `items` so concurrent flushes (e.g. a cold-start
    // notification tap on a background Task and configure() on the main thread)
    // can't mutate the array at the same time.
    private let syncQueue = DispatchQueue(label: "com.suprsend.pushQueue")
    
    init(config: SuprSendClient) {
        self.config = config
        items = UserDefaultsManager.shared.get() ?? []
        
        flush()
        
        setupReachability()
    }
    
    deinit {
        reachability.stopNotifier()
    }
    
    private var items: [PushQueueItem] {
        didSet {
            UserDefaultsManager.shared.set(items)
        }
    }
    
    private func setupReachability() {
        reachability.whenReachable = { [weak self] reachability in
            self?.flush()
        }
        reachability.whenUnreachable = { _ in
            logger.error("Not reachable")
        }
        
        do {
            try reachability.startNotifier()
        } catch {
            logger.error("Unable to start notifier")
        }
    }
    
    func push(_ item: PushQueueItem) {
        syncQueue.sync { items.append(item) }
        flush()
    }

    /// Retries any persisted/pending events. Called after `configure()` so a
    /// cold-start event queued before the public key was set (e.g. a
    /// notification tap from a killed state) gets sent once the key is available.
    func flushPendingEvents() {
        flush()
    }

    private func flush() {
        let pending = syncQueue.sync { items }
        for item in pending {
            Task {
                let response = await triggetEvent(item: item)

                // Remove only after a confirmed send. If the send fails or the
                // app is killed mid-send, the item stays persisted and is retried
                // on the next flush/launch — so events are never lost. A flush
                // overlapping an in-flight send may resend it (duplicates are
                // acceptable; lost events are not).
                if response.status != .error {
                    syncQueue.sync {
                        if let index = items.firstIndex(of: item) {
                            items.remove(at: index)
                        }
                    }
                }
            }
        }
    }

    private func triggetEvent(item: PushQueueItem) async -> APIResponse {
        await config.trackPublic(event: item.event, properties: [
            "id": item.nid
        ])
    }
}

struct PushQueueItem: Codable, Equatable {
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
