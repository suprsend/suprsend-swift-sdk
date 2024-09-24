//
//  PreferenceOptions.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 16/09/24.
//

import Foundation

public enum PreferenceOptions: String, Codable {
    /// Option to opt in for a preference
    case optIn = "opt_in"

    /// Option to opt out for a preference
    case optOut = "opt_out"
}

public enum ChannelLevelPreferenceOptions: String, Codable {
    /// All channels are allowed
    case all = "all"

    /// Only required channels are allowed
    case required = "required"
}

public struct CategoryChannel: Codable {
    /// The name of the channel
    public let channel: String

    /// The preference for this category
    public var preference: PreferenceOptions

    /// Whether this category is editable or not
    public let isEditable: Bool
}

public struct Category: Codable {
    /// The name of the category
    public let name: String

    /// The category itself
    public let category: String

    /// A brief description of the category (optional)
    public let description: String?

    /// The preference for this category
    public var preference: PreferenceOptions

    /// Whether this category is editable or not
    public let isEditable: Bool

    /// An array of subcategories (optional)
    public let channels: [CategoryChannel]?
}

public struct Section: Codable {
    /// The name of the section (optional)
    public let name: String?

    /// A brief description of the section (optional)
    public let description: String?

    /// An array of categories within this section (optional)
    public let subcategories: [Category]?
}

public struct ChannelPreference: Codable {
    /// The name of the channel
    public let channel: String

    /// Whether this channel is restricted or not
    public var isRestricted: Bool
}

public struct PreferenceData: Codable {
    /// An array of sections within this preference data (optional)
    public let sections: [Section]?

    /// An array of channel preferences (optional)
    public let channelPreferences: [ChannelPreference]?
}

public struct PreferenceAPIResponse: Response {
    /// The status of the API response
    public let status: ResponseStatus

    /// The HTTP status code of the API response (optional)
    public let statusCode: StatusCode?

    /// The body of the API response (optional)
    public let body: PreferenceData?

    /// An error message if any (optional)
    public let error: ResponseError?

    /// Initializes a `PreferenceAPIResponse` instance
    ///
    /// - Parameters:
    ///   - status: The status of the API response.
    ///   - statusCode: The HTTP status code of the API response (optional).
    ///   - body: The body of the API response (optional).
    ///   - error: An error message if any (optional).
    public init(
        status: ResponseStatus, statusCode: StatusCode?, body: PreferenceData?,
        error: ResponseError?
    ) {
        self.status = status
        self.statusCode = statusCode
        self.body = body
        self.error = error
    }
}

struct RequestPayload: Codable {
    /// The preference to be applied
    let preference: PreferenceOptions

    /// An array of channels to opt out (optional)
    let optOutChannels: [String]?

    enum CodingKeys: String, CodingKey {
        /// The `preference` key in the JSON dictionary
        case preference

        /// The `opt_out_channels` key in the JSON dictionary (optional)
        case optOutChannels = "opt_out_channels"
    }
}
