import Testing

@testable import SuprSend

struct EmitterTests {

    @Test func offRemovesOnlyThatListener() {
        let emitter = Emitter()
        var first = 0
        var second = 0
        let listener = emitter.on(.preferencesUpdated) { _ in first += 1 }
        emitter.on(.preferencesUpdated) { _ in second += 1 }

        emitter.off(listener)
        emitter.emit(event: .preferencesUpdated, data: .success())

        #expect(first == 0)
        #expect(second == 1)
    }

    @Test func offEventRemovesEveryListenerForThatEvent() {
        let emitter = Emitter()
        var errors = 0
        var updates = 0
        emitter.on(.preferencesError) { _ in errors += 1 }
        emitter.on(.preferencesError) { _ in errors += 1 }
        emitter.on(.preferencesUpdated) { _ in updates += 1 }

        emitter.off(.preferencesError)
        emitter.emit(event: .preferencesError, data: .success())
        emitter.emit(event: .preferencesUpdated, data: .success())

        #expect(errors == 0)
        #expect(updates == 1)
    }

    @Test func listenersDoNotReceiveEarlierEvents() {
        let emitter = Emitter()
        var received = 0
        emitter.emit(event: .preferencesError, data: .success())

        emitter.on(.preferencesError) { _ in received += 1 }
        #expect(received == 0)

        emitter.emit(event: .preferencesError, data: .success())
        #expect(received == 1)
    }

    @Test func discardedHandleKeepsListenerActive() {
        let emitter = Emitter()
        var received = 0
        emitter.on(.preferencesUpdated) { _ in received += 1 }

        emitter.emit(event: .preferencesUpdated, data: .success())

        #expect(received == 1)
    }
}
