//
//  Emitter.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 15/09/24.
//

import Foundation

public class Emitter {
    /// Enumerates possible events that can be emitted.
    public enum Event {
        case preferencesUpdated
        case preferencesError
    }

    /// Registers a callback to be executed when the specified event occurs.
    ///
    /// - Parameters:
    ///   - event: The event for which to register the callback.
    ///   - callback: The callback function to execute when the event occurs.
    public func on(_ event: Event, _ callback: @escaping (any Response) -> Void) {

    }

    /// Emits a specified event with associated data.
    ///
    /// - Parameters:
    ///   - event: The event to emit.
    ///   - data: The data associated with the emitted event.
    func emit(event: Event, data: some Response) {

    }
}
