//
//  ValidatedDataOptions.swift
//  SuprSend
//
//  Created by Ram Suthar on 16/09/24.
//

import Foundation

struct ValidatedDataOptions {
    let allowReservedKeys: Bool
    let valueType: ValueType?
    
    enum ValueType: String {
        case boolean
        case number
    }
}
