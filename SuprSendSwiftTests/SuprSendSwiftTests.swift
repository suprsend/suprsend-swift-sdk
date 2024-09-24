//
//  SuprSendSwiftTests.swift
//  SuprSendSwiftTests
//
//  Created by Ram Suthar on 24/09/24.
//

import Testing
@testable import SuprSendSwift

struct SuprSendSwiftTests {
    
    @Test func testEvents() async throws {
        let token = try MockJWTToken().generate(for: "hello@example.com")
        
        let client = SuprSend(
            publicKey: "SS.PUBK.1xIFmms8ZPywbFbbuJo55TXUNSMfrYls4DdNhH4Peto",
            options: .init(host: "https://collector-staging.suprsend.workers.dev", vapidKey: nil)
        )
        
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
