import Foundation
import Combine

public class Emitter {
    /// Enumerates possible events that can be emitted.
    public enum Event {
        case preferencesUpdated
        case preferencesError
    }

    /// Handle returned by ``on(_:_:)``. Pass it to ``off(_:)`` to stop receiving that event.
    public struct Listener: Hashable {
        public let event: Event
        fileprivate let id = UUID()
    }

    struct EventObject {
        let event: Event
        let data: PreferenceAPIResponse?
    }

    private let eventPublisher = PassthroughSubject<EventObject, Never>()
    private let lock = NSLock()
    private var subscriptions: [Listener: AnyCancellable] = [:]

    /// Registers a callback for an event. The listener stays active until ``off(_:)`` is called,
    /// even when the returned handle is discarded.
    /// - Parameters:
    ///   - event: The event for which to register the callback.
    ///   - callback: The callback function to execute when the event occurs.
    @discardableResult
    public func on(_ event: Event, _ callback: @escaping (PreferenceAPIResponse?) -> Void) -> Listener {
        let listener = Listener(event: event)
        let cancellable = eventPublisher
            .filter { $0.event == event }
            .sink { object in
                callback(object.data)
            }
        lock.lock()
        subscriptions[listener] = cancellable
        lock.unlock()
        return listener
    }

    /// Removes one listener.
    public func off(_ listener: Listener) {
        lock.lock()
        let cancellable = subscriptions.removeValue(forKey: listener)
        lock.unlock()
        cancellable?.cancel()
    }

    /// Removes every listener registered for an event.
    public func off(_ event: Event) {
        lock.lock()
        let removed = subscriptions.filter { $0.key.event == event }
        removed.keys.forEach { subscriptions.removeValue(forKey: $0) }
        lock.unlock()
        removed.values.forEach { $0.cancel() }
    }

    func emit(event: Event, data: PreferenceAPIResponse) {
        eventPublisher.send(.init(event: event, data: data))
    }
}
