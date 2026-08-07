//
//  File.swift
//  SuprSend
//
//  Created by Ram Suthar on 01/09/25.
//

import Foundation

enum AnyDecodable: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyDecodable])
    case array([AnyDecodable])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([AnyDecodable].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            self = .object(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown JSON type")
        }
    }
}
