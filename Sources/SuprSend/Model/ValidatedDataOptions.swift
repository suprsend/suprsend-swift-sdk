import Foundation

struct ValidatedDataOptions {
    let allowReservedKeys: Bool
    let valueType: ValueType?
    
    enum ValueType: String {
        case boolean
        case number
    }
}
