//
//  UserTokenRefreshTests.swift
//  SuprSendTests
//

import Testing
import Foundation
@testable import SuprSend

struct UserTokenRefreshTests {

    private let now: TimeInterval = 1_700_000_000

    // MARK: - Expiry window

    @Test func expiredTokenIsExpiring() {
        #expect(APIClient.isUserTokenExpiring(expiresOn: now - 1, now: now))
        #expect(APIClient.isUserTokenExpiring(expiresOn: now, now: now))
    }

    @Test func tokenInsideRefreshWindowIsExpiring() {
        let window = Constants.userTokenRefreshBefore
        #expect(APIClient.isUserTokenExpiring(expiresOn: now + window, now: now))
        #expect(APIClient.isUserTokenExpiring(expiresOn: now + window - 1, now: now))
    }

    @Test func tokenOutsideRefreshWindowIsNotExpiring() {
        let window = Constants.userTokenRefreshBefore
        #expect(!APIClient.isUserTokenExpiring(expiresOn: now + window + 1, now: now))
        #expect(!APIClient.isUserTokenExpiring(expiresOn: now + 3600, now: now))
    }

    // MARK: - In-flight coalescing

    @Test func concurrentCallersShareOneRun() async {
        let inflight = SharedInflightTask()
        let runs = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await inflight.run {
                        await runs.increment()
                        // Keep the run open long enough for every sibling to
                        // arrive and find it in flight, with generous margin
                        // for a loaded machine running other suites in parallel.
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
        }

        #expect(await runs.value == 1)
    }

    @Test func runsAgainOnceThePreviousRunHasFinished() async {
        let inflight = SharedInflightTask()
        let runs = Counter()

        await inflight.run { await runs.increment() }
        await inflight.run { await runs.increment() }

        #expect(await runs.value == 2)
    }

    @Test func everyCallerWaitsForTheSharedRunToComplete() async {
        let inflight = SharedInflightTask()
        let completed = Counter()

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await inflight.run {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await completed.increment()
                    }
                    // By the time `run` returns, the operation this caller
                    // joined must have finished — never observe zero completions.
                    // (Exactly-once sharing is covered by the test above.)
                    return await completed.value >= 1
                }
            }
            for await sawCompletion in group {
                #expect(sawCompletion)
            }
        }
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
