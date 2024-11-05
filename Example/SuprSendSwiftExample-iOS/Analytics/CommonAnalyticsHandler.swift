//
//  CommonAnalyticsHandler.swift
//  ECommerceAppSwiftUI
//
//  Created by Niks on 06/11/21.
//
//

import Foundation
import SuprSend

struct CommonAnalyticsHandler {
    
    struct TokenResponse: Decodable {
        let token: String
    }
    
    static func identify(identity: String) {
        Task { @MainActor in
            let token = await getToken(for: identity)
            _ = await SuprSend.shared.identify(distinctID: identity, userToken: token, options: AuthenticateOptions(refreshUserToken: { oldUserToken, tokenPayload in
                await getToken(for: identity)
            }))
        }
    }
    
    static func addEmail(_ email: String) {
        Task {
            await SuprSend.shared.user.addEmail(email)
        }
    }
    
    static func getToken(for identity: String) async -> String? {
        let url = "https://collector-staging.suprsend.workers.dev/authentication-token/\(identity)/"
        let response: (data: Data, response: URLResponse)? = try? await URLSession.shared.data(from: URL(string: url)!)
        if let data = response?.data {
            let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data)
            return tokenResponse?.token
        }
        return nil
    }
    
    static func track(eventName: String) {
        Task {
            await SuprSend.shared.track(event: eventName)
        }
    }
    
    static func track(eventName: String, properties: [String : Encodable]) {
        Task {
            await SuprSend.shared.track(event: eventName, properties: properties)
        }
    }
    
    static func set(key: String, value: String) {
        Task {
            await SuprSend.shared.user.set(key: key, value:  value)
        }
    }
    
    static func set(properties: [String : Encodable]) {
        Task {
            await SuprSend.shared.user.set(properties: properties)
        }
    }
    
    static func increment(key: String, value: Float) {
        Task {
            await SuprSend.shared.user.increment(key: key, value: value)
        }
    }
    
    static func increment(properties: [String: Float]) {
        Task {
            await SuprSend.shared.user.increment(properties: properties)
        }
    }
    
    static func append(key: String, value: String) {
        Task {
            await SuprSend.shared.user.append(key: key, value: value)
        }
    }
    
    static func remove(key: String, value: String) {
        Task {
            await SuprSend.shared.user.remove(key: key, value: value)
        }
    }
    
    static func unset(key: String) {
        Task {
            await SuprSend.shared.user.unset(key:key)
        }
    }
    
    static func setSms(mobileNumber: String) {
        Task {
            await SuprSend.shared.user.addSMS(mobileNumber)
        }
    }
    
    static func reset(unsubscribePushNotification: Bool) async {
        await SuprSend.shared.reset(options: .init(unsubscribePush: unsubscribePushNotification))
    }
    
    static func setOnce(key: String, value: Encodable) {
        Task {
            await SuprSend.shared.user.setOnce(key: key, value: value)
        }
    }
    
    static func setOnce(properties: [String : Encodable]) {
        Task {
            await SuprSend.shared.user.setOnce(properties:properties)
        }
    }
    
    static func setSuperProperties(key: String, value: Encodable) {
        Task {
//            await SuprSend.shared.user.setSuperProperty(key: key, value: value)
        }
    }
    
    static func setSuperProperties(jsonObject: [String: Encodable]) {
        Task {
//            await SuprSend.shared.user.setSuperProperties(properties: jsonObject)
        }
    }
    
    static func unSetSuperProperties(key: String) {
//        await SuprSend.shared.unSetSuperProperty(key:key)
    }
    
    static func purchaseMade(properties: [String : Encodable]) {
//        await SuprSend.shared.purchaseMade(properties:properties)
    }
}
