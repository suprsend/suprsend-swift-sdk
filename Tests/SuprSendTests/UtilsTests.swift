//
//  UtilsTests.swift
//  SuprSendTests
//
//  Created by Ram Suthar on 16/09/24.
//

import Foundation
import Testing

@testable import SuprSend

struct UtilsTests {
    @Test
    func textPhoneValidation() throws {
        let phone = "+14151231234"
        #expect(Utils.shared.validatePhone(phone: phone))
        
        let invalidPhone = "14151231234"
        #expect(Utils.shared.validatePhone(phone: invalidPhone) == false)
    }
    
    @Test func textEmailValidation() async throws {
        let email = "hello@example.com"
        #expect(Utils.shared.validateEmail(email: email))
        
        let invalidEmail = "helloexample.com"
        #expect(Utils.shared.validateEmail(email: invalidEmail) == false)
    }
    
    @Test func testIsReservedKey() {
        #expect(Utils.shared.isReservedKey("$key"))
        #expect(Utils.shared.isReservedKey("ss_key"))
        #expect(!Utils.shared.isReservedKey("key"))
    }
    
    @Test func testValidateArrayData() {
        let data = ["$value", "value", "ss_value"]
        #expect(Utils.shared.validateArrayData(data: data) == ["value"])
    }
    
    @Test func testValidateObjData() {
        let data: EventProperty = ["$key": "value", "key": "value", "ss_key": "value"]
        let filteredData = Utils.shared.validateObjData(data: data)
        #expect(!filteredData.keys.contains("$key"))
        #expect(!filteredData.keys.contains("ss_key"))
        #expect(filteredData.keys.contains("key"))
    }
    
    @Test func testValidateObjDataWithOptions() {
        let data: EventProperty = ["$key": "value", "key": "value", "ss_key": "value"]
        let filteredData = Utils.shared.validateObjData(data: data, options: .init(allowReservedKeys: true, valueType: nil))
        #expect(filteredData.keys.contains("$key"))
        #expect(filteredData.keys.contains("ss_key"))
        #expect(filteredData.keys.contains("key"))
    }
    
    @Test func testDecodeJWTToken() throws {
        let decoded = try Utils.shared.decode(jwtToken: "eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiJ9.eyJpYXQiOjE3MjY1NjQ3MTIsImVudGl0eV90eXBlIjoic3Vic2NyaWJlciIsImVudGl0eV9pZCI6InJlYWxseXJhbUBnbWFpbC5jb20iLCJleHAiOjE3MjY1NjgzMTJ9.VT_nlxwi4hmNp26q_tpw6YRk_AoJ-38p5_DZixnCXq3Ke_TkYfAyFDHWx8UFpeT9mMrmreV8ZVQx5KRnKkthiQ")
        #expect(decoded != nil)
        #expect(decoded["exp"] as? Int == 1726568312)
        
        #expect((try? Utils.shared.decode(jwtToken: "")) == nil)
    }
    
    @Test func testLocalStorageData() {
        Utils.shared.setLocalStorageData(key: "test_key", value: "test_value")
        #expect(Utils.shared.getLocalStorageData(key: "test_key") == "test_value")
       
        Utils.shared.removeLocalStorageData(key: "test_key")
        #expect(Utils.shared.getLocalStorageData(key: "test_key") == nil)
    }
}
