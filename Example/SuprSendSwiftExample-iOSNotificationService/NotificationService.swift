//
//  NotificationService.swift
//  SuprSendExample-iOSNotificationService
//
//  Created by Ram Suthar on 24/09/24.
//

import UserNotifications
import UIKit
import SuprSend

class NotificationService: SuprSendNotificationService {
    override func publicKey() -> String {
        SuprSendConstants.publicKey
    }
    
    override func options() -> SuprSend.Options? {
        .init(host: SuprSendConstants.host)
    }
}
