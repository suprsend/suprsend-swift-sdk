//
//  PreferenceOptions.swift
//  SuprSend
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

public class CategoryChannel: Codable {
    /// The name of the channel
    public let channel: String

    /// The preference for this category
    public var preference: PreferenceOptions

    /// Whether this category is editable or not
    public let isEditable: Bool
    
    enum CodingKeys: String, CodingKey {
        case channel
        case preference
        case isEditable = "is_editable"
    }
}

public class Category: Codable {
    /// The name of the category
    public let name: String

    /// The category itself
    public let category: String

    /// A brief description of the category (optional)
    public let description: String?

    /// The preference for this category
    public var preference: PreferenceOptions
    
    /// The preference for this category
//    public var originalPreference: PreferenceOptions

    /// Whether this category is editable or not
    public let isEditable: Bool

    /// An array of subcategories (optional)
    public let channels: [CategoryChannel]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case category
        case description
        case preference
//        case originalPreference = "original_preference"
        case isEditable = "is_editable"
        case channels
    }
}

public class Section: Codable {
    /// The name of the section (optional)
    public let name: String?

    /// A brief description of the section (optional)
    public let description: String?

    /// An array of categories within this section (optional)
    public let subcategories: [Category]?
}

public class ChannelPreference: Codable {
    /// The name of the channel
    public let channel: String

    /// Whether this channel is restricted or not
    public var isRestricted: Bool
    
    enum CodingKeys: String, CodingKey {
        case channel
        case isRestricted = "is_restricted"
    }
}

public class PreferenceData: Codable {
    /// An array of sections within this preference data (optional)
    public let sections: [Section]?

    /// An array of channel preferences (optional)
    public let channelPreferences: [ChannelPreference]?
    
    enum CodingKeys: String, CodingKey {
        case sections
        case channelPreferences = "channel_preferences"
    }
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
    
    public init(from decoder: any Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        self.status = try container.decode(ResponseStatus.self, forKey: .status)
//        self.statusCode = try container.decodeIfPresent(StatusCode.self, forKey: .statusCode)
        self.body = try PreferenceData(from: decoder)
//        self.error = try container.decodeIfPresent(ResponseError.self, forKey: .error)
        
        self.status = .success
        self.statusCode = nil
        self.error = nil
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


struct ChannelRequestPayload: Codable {
    /// An array of channel preferences (optional)
    public let channelPreferences: [ChannelPreference]
    
    enum CodingKeys: String, CodingKey {
        
        /// The `channel_preferences` key in the JSON dictionary (optional)
        case channelPreferences = "channel_preferences"
    }
}
