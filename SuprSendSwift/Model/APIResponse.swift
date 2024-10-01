//
//  APIResponse.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 24/08/24.
//

import Foundation

/// A type alias for a HTTP status code.
public typealias StatusCode = Int

/// A type alias for a JSON response body.
public typealias ResponseBody = [String: String]

/// The `Response` protocol defines the structure of an API response.
///
/// This protocol is used to represent responses from APIs, and provides a way to
/// encapsulate the status, status code, body, and error information in a single
/// struct.
public protocol Response: Codable {
    associatedtype Body

    /// The status of the response (e.g. success or error).
    var status: ResponseStatus { get }

    /// The HTTP status code associated with the response.
    var statusCode: StatusCode? { get }

    /// The JSON response body.
    var body: Body? { get }

    /// Any error that occurred during the request.
    var error: ResponseError? { get }

    init(
        status: ResponseStatus,
        statusCode: StatusCode?,
        body: Body?,
        error: ResponseError?
    )
}

/// The `ResponseStatus` enum defines the possible statuses of an API response.
///
/// This enum is used to represent the status of a response, and provides a way
/// to encapsulate the different types of responses in a single struct.
public enum ResponseStatus: String, Codable {
    case success = "success"
    case error = "error"
}

/// The `ResponseError` struct defines an error that occurred during a request.
///
/// This struct is used to represent any errors that occur during a request,
/// and provides a way to encapsulate the type and message of the error in a single
/// struct.
public struct ResponseError: Codable {
    /// The type of error that occurred (e.g. unknown, validation, etc.).
    public let type: ErrorType?

    /// A message describing the error.
    public let message: String?
}

/// The `ErrorType` enum defines the possible types of errors that can occur.
///
/// This enum is used to represent the type of an error, and provides a way
/// to encapsulate the different types of errors in a single struct.
public enum ErrorType: String, Codable {
    case unknown = "UNKNOWN_ERROR"
    case validation = "VALIDATION_ERROR"
    case network = "NETWORK_ERROR"
    case permissionDenied = "PERMISSION_DENIED"
    case unsupportedAction = "UNSUPPORTED_ACTION"
    case tokenInvalid = "token_invalid"
}

/// The `APIResponse` struct defines an API response.
///
/// This struct is used to represent a response from an API, and provides a way
/// to encapsulate the status, status code, body, and error information in a single
/// struct.
public class APIResponse: NSObject, Response {
    /// The status of the response (e.g. success or error).
    public let status: ResponseStatus

    /// The HTTP status code associated with the response.
    public let statusCode: StatusCode?

    /// The JSON response body.
    public let body: ResponseBody?

    /// Any error that occurred during the request.
    public let error: ResponseError?

    required public init(
        status: ResponseStatus,
        statusCode: StatusCode?,
        body: ResponseBody?,
        error: ResponseError?
    ) {
        self.status = status
        self.statusCode = statusCode
        self.body = body
        self.error = error
    }
}

extension Response {
    /// Creates a new instance of the response struct with a success status.
    static func success(
        statusCode: StatusCode? = nil,
        body: Body? = nil
    ) -> Self {
        Self.init(
            status: .success,
            statusCode: statusCode,
            body: body,
            error: nil
        )
    }

    /// Creates a new instance of the response struct with an error status.
    static func error(
        _ error: ResponseError?,
        statusCode: StatusCode? = nil
    ) -> Self {
        Self.init(
            status: .error,
            statusCode: statusCode,
            body: nil,
            error: error
        )
    }
}
