//
//  ResetOption.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 25/08/24.
//

import Foundation

public struct ResetOption {
    let unsubscribePush: Bool
    
    public init(unsubscribePush: Bool) {
        self.unsubscribePush = unsubscribePush
    }
}
