import Foundation

public struct ResetOption {
    let unsubscribePush: Bool
    
    public init(unsubscribePush: Bool) {
        self.unsubscribePush = unsubscribePush
    }
}
