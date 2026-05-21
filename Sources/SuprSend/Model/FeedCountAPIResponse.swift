//
//  FeedCountAPIResponse.swift
//  SuprSend
//
//  Created by Ram Suthar on 31/07/25.
//

import Foundation

public struct FeedCountAPIResponse: Response {
    /// The status of the API response
    public let status: ResponseStatus
    
    /// The HTTP status code of the API response (optional)
    public let statusCode: StatusCode?
    
    /// The body of the API response (optional)
    public let body: FeedCountData?
    
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
        status: ResponseStatus, statusCode: StatusCode?, body: FeedCountData?,
        error: ResponseError?
    ) {
        self.status = status
        self.statusCode = statusCode
        self.body = body
        self.error = error
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = (try? container.decodeIfPresent(ResponseStatus.self, forKey: .status)) ?? .success
        self.statusCode = try container.decodeIfPresent(StatusCode.self, forKey: .statusCode)
        self.error = try container.decodeIfPresent(ResponseError.self, forKey: .error)
        
        self.body = try FeedCountData(from: decoder)
    }
}

public struct FeedCountData: Codable {
    public let badge: UInt?
}
