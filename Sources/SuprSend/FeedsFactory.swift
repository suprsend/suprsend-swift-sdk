import Foundation

public class FeedsFactory {
    private let config: SuprSendClient
    private(set) var feedInstances: [Feed] = []
    
    init(config: SuprSendClient) {
        self.config = config
    }
    
    public func initialize(options: IFeedOptions? = nil) -> Feed {
        let feedClient = Feed(config: config, options: options)
        feedInstances.append(feedClient)
        return feedClient
    }
    
    public func removeInstance(_ feedClient: Feed) {
        feedInstances.removeAll { $0 === feedClient }
    }
    
    public func removeAll() {
        feedInstances.forEach { $0.remove() }
        feedInstances = []
    }
}
