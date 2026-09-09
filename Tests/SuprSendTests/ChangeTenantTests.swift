//
//  ChangeTenantTests.swift
//  SuprSendTests
//

import Testing
@testable import SuprSend

/// `changeTenant` paths that need no network and no push registration: input
/// validation, the default `.none` action, and `.copy` / `.move` before a user
/// is identified (where the token step is skipped and the tenant still moves).
struct ChangeTenantTests {

    @Test func emptyTenantIdIsRejectedAndLeavesTenantUnchanged() async {
        let client = SuprSendClient(publicKey: "test-key")

        let response = await client.changeTenant(tenantId: "")

        #expect(response.status == .error)
        #expect(response.error?.type == .validation)
        #expect(client.tenantId == nil)
    }

    @Test func defaultActionSwitchesTenant() async {
        let client = SuprSendClient(publicKey: "test-key")

        let response = await client.changeTenant(tenantId: "tenant-a")

        #expect(response.status == .success)
        #expect(client.tenantId == "tenant-a")
    }

    @Test func copyAndMoveBeforeIdentifyStillSwitchTenant() async {
        let client = SuprSendClient(publicKey: "test-key")

        let copy = await client.changeTenant(tenantId: "tenant-a", pushTokenAction: .copy)
        #expect(copy.status == .success)
        #expect(client.tenantId == "tenant-a")

        let move = await client.changeTenant(tenantId: "tenant-b", pushTokenAction: .move)
        #expect(move.status == .success)
        #expect(client.tenantId == "tenant-b")
    }

    @Test func switchingToTheSameTenantSucceeds() async {
        let client = SuprSendClient(publicKey: "test-key")
        _ = await client.changeTenant(tenantId: "tenant-a")

        let response = await client.changeTenant(tenantId: "tenant-a", pushTokenAction: .move)

        #expect(response.status == .success)
        #expect(client.tenantId == "tenant-a")
    }
}
