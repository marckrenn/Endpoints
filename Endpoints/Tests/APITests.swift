//
//  EndpointTests.swift
//  EndpointTests
//
//  Created by Peter W on 10/10/2016.
//  Copyright © 2016 Tailored Apps. All rights reserved.
//

import XCTest
@testable import Endpoints

class APITests: APITestCase {
    override func setUp() {
        api = API(baseURL: URL(string: "http://httpbin.org")!)
        api.debugAll = true
    }
    
    func testTimeoutError() {
        let request = DynamicRequest<Data>(.get, "delay/1")
        
        let exp = expectation(description: "")
        var req = api.request(for: request)
        req.timeoutInterval = 0.5
        
        api.start(request: req, responseType: Data.self) { result in
            self.assert(result: result, isSuccess: false)
            XCTAssertNil(result.response?.statusCode)
            
            let error = result.error as! URLError
            XCTAssertEqual(error.code, URLError.timedOut)
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testStatusError() {
        let request = DynamicRequest<Data>(.get, "status/400")
        
        test(endpoint: request) { result in
            self.assert(result: result, isSuccess: false, status: 400)
            
            if let error = result.error as? APIError {
                switch error {
                case .unacceptableStatus:
                    print("got expected error: \(error)")
                default:
                    XCTFail("wrong error type \(error)")
                }
            } else {
                XCTFail("wrong error: \(result.error)")
            }
        }
    }
    
    func testGetData() {
        let request = DynamicRequest<Data>(.get, "get")
        
        test(endpoint: request) { result in
            self.assert(result: result, isSuccess: true, status: 200)
        }
    }
    
    func testGetString() {
        let request = DynamicRequest<String>(.get, "get", query: [ "inputParam" : "inputParamValue" ])
        
        test(endpoint: request) { result in
            self.assert(result: result, isSuccess: true, status: 200)
            
            if let string = result.value {
                XCTAssertTrue(string.contains("inputParamValue"))
            }
        }
    }
    
    func testGetJSONDictionary() {
        let request = DynamicRequest<[String: Any]>(.get, "get", query: [ "inputParam" : "inputParamValue" ])
        
        test(endpoint: request) { result in
            self.assert(result: result, isSuccess: true, status: 200)
            
            if let jsonDict = result.value {
                let args = jsonDict["args"]
                XCTAssertNotNil(args)
                
                if let args = args {
                    XCTAssertTrue(args is Dictionary<String, String>)
                    
                    if let args = args as? Dictionary<String, String> {
                        let param = args["inputParam"]
                        XCTAssertNotNil(param)
                        
                        if let param = param {
                            XCTAssertEqual(param, "inputParamValue")
                        }
                    }
                }
            }
        }
    }
    
    func testParseJSONArray() {
        let inputArray = [ "one", "two", "three" ]
        let arrayData = try! JSONSerialization.data(withJSONObject: inputArray, options: .prettyPrinted)

        let parsedObject = try! DynamicRequest<[String]>.ResponseType.parse(responseData: arrayData, encoding: .utf8)!
        
        XCTAssertEqual(inputArray, parsedObject)
    }
    
    func testFailJSONParsing() {
        let request = DynamicRequest<[String: Any]>(.get, "xml")
        
        test(endpoint: request) { result in
            self.assert(result: result, isSuccess: false, status: 200)
            
            if let error = result.error as? CocoaError {
                XCTAssertTrue(error.isPropertyListError)
                XCTAssertEqual(error.code, CocoaError.Code.propertyListReadCorrupt)
            } else {
                XCTFail("wrong error: \(result.error)")
            }
        }
    }
    
    struct GetOutput: Request {
        typealias RequestType = GetOutput
        typealias ResponseType = [String: Any]
        
        let value: String
        
        var path: String? { return "get" }
        var method: HTTPMethod { return .get }
        
        var query: Parameters? {
            return [ "param" : value ]
        }
    }
    
    func testTypedRequest() {
        let value = "value"
        
        test(endpoint: GetOutput(value: value)) { result in
            self.assert(result: result)
            
            if let jsonDict = result.value {
                let args = jsonDict["args"]
                XCTAssertNotNil(args)
                
                if let args = args {
                    XCTAssertTrue(args is Dictionary<String, String>)
                    
                    if let args = args as? Dictionary<String, String> {
                        let param = args["param"]
                        XCTAssertNotNil(param)
                        
                        if let param = param {
                            XCTAssertEqual(param, value)
                        }
                    }
                }
            }
        }
    }
}
