//
//  SuprSendTests.swift
//  SuprSendTests
//
//  Created by Ram Suthar on 24/09/24.
//

import Testing
import Foundation
@testable import SuprSend

struct SuprSendTests {
    
    @Test func testEvents() async throws {
        let token: String = try MockJWTToken().generate(for: "hello@example.com")
        
        SuprSend.shared.configure(
            publicKey: "<YOUR_PUBLIC_KEY>",
            options: .init(host: "<CUSTOM_HOST_URL>")
        )
        
        let client =  SuprSend.shared
        
        let response = await client.identify(
            distinctID: "hello@example.com",
            userToken: token,
            options: .init(
                refreshUserToken: {
                    oldUserToken,
                    tokenPayload in
                    return token
                })
        )
        
        #expect(response.error?.type == nil)
        #expect(response.error?.message == nil)
        
        let event = await client.track(event: "App Launch", properties: ["Time": Date.now])
        #expect(event.error?.message == nil)
        
        let userPhone = await client.user.addSMS("+14151231234")
        #expect(userPhone.error?.message == nil)
        
        let userEmail = await client.user.addEmail("hello@example.com")
        #expect(userEmail.error?.message == nil)
    }


}
