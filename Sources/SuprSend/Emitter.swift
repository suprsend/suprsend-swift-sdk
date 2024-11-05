//
//  Emitter.swift
//  SuprSend
//
//  Created by Ram Suthar on 15/09/24.
//

import Foundation
import Combine

public class Emitter {
    /// Enumerates possible events that can be emitted.
    public enum Event {
        case preferencesUpdated
        case preferencesError
    }
    
    struct EventObject {
        let event: Event
        let data: PreferenceAPIResponse?
    }
    
    var eventPublisher: CurrentValueSubject<EventObject, Never>
    var subscriptions: Set<AnyCancellable> = []
    
    init() {
        eventPublisher = .init(.init(event: .preferencesUpdated, data: nil))
    }

    /// Registers a callback to be executed when the specified event occurs.
    ///
    /// - Parameters:
    ///   - event: The event for which to register the callback.
    ///   - callback: The callback function to execute when the event occurs.
    public func on(_ event: Event, _ callback: @escaping (PreferenceAPIResponse?) -> Void) {
        eventPublisher
            .filter { $0.event == event }
            .sink { object in
                callback(object.data)
            }
            .store(in: &subscriptions)
    }

    /// Emits a specified event with associated data.
    ///
    /// - Parameters:
    ///   - event: The event to emit.
    ///   - data: The data associated with the emitted event.
    func emit(event: Event, data: PreferenceAPIResponse) {
        eventPublisher.send(.init(event: event, data: data))
    }
}
