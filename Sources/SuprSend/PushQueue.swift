import Foundation

class PushQueue {
    
    private let userDefaultsKey: String = "PushQueueItems"
    
    let config: SuprSendClient

    let reachability = try! Reachability()

    // Serialises items against concurrent flushes (cold-start tap vs configure()).
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

    func flushPendingEvents() {
        flush()
    }

    private func flush() {
        let pending = syncQueue.sync { items }
        for item in pending {
            Task {
                let response = await triggetEvent(item: item)

                // Remove only after a confirmed send: duplicates are acceptable, lost events are not.
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
