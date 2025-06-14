//
//  User.swift
//  SuprSend
//
//  Created by Ram Suthar on 25/08/24.
//

import Foundation

public class User {

    /// The user's preferences.
    public let preferences: Preferences

    private let config: SuprSendClient

    private var distinctID: String {
        config.distinctID ?? .init()
    }

    /// Initializes a new instance of `User` with the given configuration.
    /// - Parameter config: The configuration to use for this user.
    init(config: SuprSendClient) {
        self.config = config
        self.preferences = Preferences(config: config)
    }

    /// Triggers an event on the user's behalf, sending a request to the API.
    /// This method is used internally by other methods in this class. It takes
    /// an `EventProperties` object and sends it to the API using the provided configuration.
    /// - Parameter eventProperties: The properties of the event to trigger.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    private func triggerUserEvent(_ eventProperties: UserProperty.EventProperties) async
        -> APIResponse
    {
        let event = UserProperty(
            insertID: UUID().uuidString,
            time: Date().timeIntervalSince1970,
            distinctID: distinctID,
            eventProperties: eventProperties
        )
        return await config.eventApi(payload: .init(event))
    }

    /// Retrieves the device ID associated with this user.
    /// If a device ID has been previously stored, it is returned. Otherwise, a new device ID is generated and stored for future use.
    private func getDeviceID() -> String {
        let deviceID = Utils.shared.getLocalStorageData(key: Constants.deviceIDKey)

        if let deviceID {
            return deviceID
        } else {
            let deviceID = UUID().uuidString
            Utils.shared.setLocalStorageData(key: Constants.deviceIDKey, value: deviceID)
            return deviceID
        }
    }

    /// Creates an event with the given type and properties.
    /// - Parameter type: The type of event to create.
    /// - Parameter properties: The properties of the event.
    /// - Returns: An array containing a single key-value pair, where the key is the event type and the value is the event properties.
    private func event(type: UserProperty.EventType, properties: EventProperty) -> [UserProperty
        .EventType: Property]
    {
        [type: Utils.shared.validateObjData(data: properties).convertToProperty()]
    }

    /// Creates an event with the given type and array of string properties.
    /// - Parameter type: The type of event to create.
    /// - Parameter properties: An array of strings representing the event properties.
    /// - Returns: An array containing a single key-value pair, where the key is the event type and the value is the event properties.
    private func event(type: UserProperty.EventType, properties: [String]) -> [UserProperty
        .EventType: Property]
    {
        [type: .init(Utils.shared.validateArrayData(data: properties))]
    }

    /// Creates an event with the given type and channel properties.
    /// - Parameter type: The type of event to create.
    /// - Parameter properties: A dictionary representing the channel properties.
    /// - Returns: An array containing a single key-value pair, where the key is the event type and the value is the event properties.
    private func event(type: UserProperty.EventType, properties: ChannelProperty) -> [UserProperty
        .EventType: Property]
    {
        [type: properties.convertToProperty()]
    }
}

// MARK: - Property Methods
extension User {

    /// Sets a single user property with the given key and value.
    /// This method takes an `Encodable` object as the value to set, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter key: The key of the property to set.
    /// - Parameter value: The value to set for the property.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func set(key: String, value: Encodable) async -> APIResponse {
        await set(properties: [key: value])
    }

    /// Sets multiple user properties at once.
    /// This method takes an `EventProperty` object as the properties to set, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter properties: The properties to set for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func set(properties: EventProperty) async -> APIResponse {
        let event = event(type: .set, properties: properties)
        return await triggerUserEvent(event)
    }

    /// Sets a single user property with the given key and value, only once.
    /// This method takes an `Encodable` object as the value to set, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter key: The key of the property to set.
    /// - Parameter value: The value to set for the property.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func setOnce(key: String, value: Encodable) async -> APIResponse {
        await setOnce(properties: [key: value])
    }

    /// Sets multiple user properties at once, only once.
    /// This method takes an `EventProperty` object as the properties to set, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter properties: The properties to set for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func setOnce(properties: EventProperty) async -> APIResponse {
        let event = event(type: .setOnce, properties: properties)
        return await triggerUserEvent(event)
    }

    /// Increments a single user property by the given amount.
    /// This method takes an `Int` value to increment by, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter key: The key of the property to increment.
    /// - Parameter value: The amount to increment the property by.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func increment(key: String, value: Float) async -> APIResponse {
        await increment(properties: [key: value])
    }

    /// Increments multiple user properties at once.
    /// This method takes an array of key-value pairs representing the properties to increment, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter properties: An array of key-value pairs representing the properties to increment.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func increment(properties: [String: Float]) async -> APIResponse {
        let event = event(type: .add, properties: properties)
        return await triggerUserEvent(event)
    }

    /// Appends a single user property to its current value.
    /// This method takes an `Encodable` object as the value to append, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter key: The key of the property to append to.
    /// - Parameter value: The value to append to the property.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func append(key: String, value: Encodable) async -> APIResponse {
        await append(properties: [key: value])
    }

    /// Appends multiple user properties at once.
    /// This method takes an `EventProperty` object as the properties to append, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter properties: The properties to append for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func append(properties: EventProperty) async -> APIResponse {
        let event = event(type: .append, properties: properties)
        return await triggerUserEvent(event)
    }

    /// Removes a single user property by its key.
    /// This method takes a `String` value as the key of the property to remove, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter key: The key of the property to remove.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func remove(key: String, value: Encodable) async -> APIResponse {
        await remove(properties: [key: value])
    }

    /// Removes multiple user properties at once.
    /// This method takes an `EventProperty` object as the properties to remove, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter properties: The properties to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func remove(properties: EventProperty) async -> APIResponse {
        let event = event(type: .remove, properties: properties)
        return await triggerUserEvent(event)
    }

    /// Unsets multiple user properties at once.
    /// This method takes an array of `String` values representing the keys to unset, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter keys: An array of keys to unset for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func unset(key: String) async -> APIResponse {
        await unset(keys: [key])
    }

    /// Unsets multiple user properties at once.
    /// This method takes an array of `String` values representing the keys to unset, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter keys: An array of keys to unset for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func unset(keys: [String]) async -> APIResponse {
        let event = event(type: .unset, properties: keys)
        return await triggerUserEvent(event)
    }
}

// MARK: - Channel Methods
typealias ChannelProperty = [ChannelType: Encodable]

extension ChannelProperty {

    /// Converts this channel property to a `Property` object.
    /// This method takes no parameters and returns a promise that resolves with a `Property` object representing the converted channel property.
    /// - Returns: A promise that resolves with a `Property` object representing the converted channel property, or rejects with an error if one occurs.
    func convertToProperty() -> Property {
        .init(compactMapValues { AnyEncodable($0) })
    }
}

extension User {

    /// Adds a push notification token for this user.
    /// This method takes a `String` value representing the push notification token, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter token: The push notification token to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addiOSPush(_ token: String) async -> APIResponse {
        let event = event(
            type: .append,
            properties: [
                .iOSPush: token,
                .deviceID: getDeviceID(),
                .pushVendor: Constants.pushVendor,
            ]
        )
        config.deviceToken = token
        return await triggerUserEvent(event)
    }

    /// Removes a push notification token for this user.
    /// This method takes a `String` value representing the push notification token, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter token: The push notification token to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeiOSPush(_ token: String) async -> APIResponse {
        let event = event(
            type: .remove,
            properties: [
                .iOSPush: token,
                .deviceID: getDeviceID(),
                .pushVendor: Constants.pushVendor,
            ]
        )
        return await triggerUserEvent(event)
    }

    /// Adds an email address for this user.
    /// This method takes a `String` value representing the email address, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter email: The email address to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addEmail(_ email: String) async -> APIResponse {
        let isValidEmail = Utils.shared.validateEmail(email: email)
        guard isValidEmail else {
            return .error(.init(type: .validation, message: "provided email is invalid"))
        }

        let event = event(type: .append, properties: [.email: email])
        return await triggerUserEvent(event)
    }

    /// Removes an email address for this user.
    /// This method takes a `String` value representing the email address, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter email: The email address to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeEmail(_ email: String) async -> APIResponse {
        let isValidEmail = Utils.shared.validateEmail(email: email)
        guard isValidEmail else {
            return .error(.init(type: .validation, message: "provided email is invalid"))
        }

        let event = event(type: .remove, properties: [.email: email])
        return await triggerUserEvent(event)
    }

    /// Adds an SMS number for this user.
    /// This method takes a `String` value representing the SMS number, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter mobile: The SMS number to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addSMS(_ mobile: String) async -> APIResponse {
        guard Utils.shared.validatePhone(phone: mobile) else {
            return .error(
                .init(
                    type: .validation,
                    message: "provided mobile number is invalid, must be as per E.164 standard"))
        }

        let event = event(type: .append, properties: [.sms: mobile])
        return await triggerUserEvent(event)
    }

    /// Removes an SMS number for this user.
    /// This method takes a `String` value representing the SMS number, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter mobile: The SMS number to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeSMS(_ mobile: String) async -> APIResponse {
        guard Utils.shared.validatePhone(phone: mobile) else {
            return .error(
                .init(
                    type: .validation,
                    message: "provided mobile number is invalid, must be as per E.164 standard"))
        }

        let event = event(type: .remove, properties: [.sms: mobile])
        return await triggerUserEvent(event)
    }

    /// Adds a WhatsApp number for this user.
    /// This method takes a `String` value representing the WhatsApp number, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter mobile: The WhatsApp number to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addWhatsapp(_ mobile: String) async -> APIResponse {
        guard Utils.shared.validatePhone(phone: mobile) else {
            return .error(
                .init(
                    type: .validation,
                    message: "provided mobile number is invalid, must be as per E.164 standard"))
        }

        let event = event(type: .append, properties: [.whatsapp: mobile])
        return await triggerUserEvent(event)
    }

    /// Removes a WhatsApp number for this user.
    /// This method takes a `String` value representing the WhatsApp number, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter mobile: The WhatsApp number to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeWhatsapp(_ mobile: String) async -> APIResponse {
        guard Utils.shared.validatePhone(phone: mobile) else {
            return .error(
                .init(
                    type: .validation,
                    message: "provided mobile number is invalid, must be as per E.164 standard"))
        }

        let event = event(type: .remove, properties: [.whatsapp: mobile])
        return await triggerUserEvent(event)
    }

    /// Adds Slack data for this user.
    /// This method takes an `Encodable` object representing the Slack data, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter data: The Slack data to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addSlack(_ data: Encodable) async -> APIResponse {
        let event = event(type: .append, properties: [.slack: data])
        return await triggerUserEvent(event)
    }

    /// Removes Slack data for this user.
    /// This method takes an `Encodable` object representing the Slack data, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter data: The Slack data to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeSlack(_ data: Encodable) async -> APIResponse {
        let event = event(type: .remove, properties: [.slack: data])
        return await triggerUserEvent(event)
    }

    /// Adds Microsoft Teams data for this user.
    /// This method takes an `Encodable` object representing the Microsoft Teams data, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter data: The Microsoft Teams data to add for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func addMSTeams(_ data: Encodable) async -> APIResponse {
        let event = event(type: .append, properties: [.msTeams: data])
        return await triggerUserEvent(event)
    }

    /// Removes Microsoft Teams data for this user.
    /// This method takes an `Encodable` object representing the Microsoft Teams data, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter data: The Microsoft Teams data to remove for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func removeMSTeams(_ data: Encodable) async -> APIResponse {
        let event = event(type: .remove, properties: [.msTeams: data])
        return await triggerUserEvent(event)
    }

    /// Sets the preferred language for this user.
    /// This method takes a `String` value representing the preferred language, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter language: The preferred language to set for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func setPreferredLanguage(_ language: String) async -> APIResponse {
        let event = event(type: .set, properties: [.preferredLanguage: language])
        return await triggerUserEvent(event)
    }

    /// Sets the timezone for this user.
    /// This method takes a `String` value representing the timezone, and returns a promise that resolves with a response from the API, or rejects with an error if one occurs.
    /// - Parameter timezone: The timezone to set for this user.
    /// - Returns: A promise that resolves with a response from the API, or rejects with an error if one occurs.
    public func setTimezone(_ timezone: String) async -> APIResponse {
        let event = event(type: .set, properties: [.timezone: timezone])
        return await triggerUserEvent(event)
    }
}
