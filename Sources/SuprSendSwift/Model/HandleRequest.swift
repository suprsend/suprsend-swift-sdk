//
//  HandleRequest.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 16/09/24.
//

import Foundation

struct HandleRequest {
    let path: String
    let payload: AnyEncodable?
    let type: RequestType
    
    enum RequestType: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
    }
}
