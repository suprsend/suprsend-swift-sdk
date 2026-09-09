//
//  PushTokenAction.swift
//  SuprSend
//

import Foundation

/// What ``SuprSendClient/changeTenant(tenantId:pushTokenAction:)`` does with
/// the device's push token when switching tenants. Mirrors `pushTokenAction`
/// in suprsend-web-sdk.
@objc public enum PushTokenAction: Int {
    /// Leave the token attached to the current tenant (default). The switch
    /// behaves exactly as it did before this option existed.
    case none
    /// Attach the token to the new tenant as well, keeping it on the current one.
    case copy
    /// Detach the token from the current tenant, then attach it to the new one.
    case move
}
