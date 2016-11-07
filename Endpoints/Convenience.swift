//
//  Convenience.swift
//  Endpoints
//
//  Created by Peter W on 05/11/2016.
//  Copyright © 2016 Tailored Apps. All rights reserved.
//

import Foundation

public struct BasicAuthorization {
    let user: String
    let password: String
    
    public var key: String {
        return "Authorization"
    }
    
    public var value: String {
        var value = "\(user):\(password)"
        let data = value.data(using: .utf8)!
        
        value = data.base64EncodedString(options: .endLineWithLineFeed)
        
        return "Basic \(value)"
    }
    
    public var header: Parameters {
        return [ key: value ]
    }
}

public struct DynamicCall<Response: DataParser>: Call {
    public typealias ResponseType = Response
    
    public typealias EncodingBlock = (inout URLRequest)->()
    public typealias ValidationBlock = (URLSessionTaskResult) throws ->()
    
    public var request: URLRequestEncodable
    
    public var encode: EncodingBlock?
    public var validate: ValidationBlock?
    
    public var urlRequest: URLRequest {
        var urlRequest = request.urlRequest
        encode?(&urlRequest)
        
        return urlRequest
    }
    
    public init(_ request: URLRequestEncodable, encode: EncodingBlock?=nil, validate: ValidationBlock?=nil) {
        self.request = request
        
        self.validate = validate
        self.encode = encode
    }
    
    public func validate(result: URLSessionTaskResult) throws {
        try validate?(result)
    }
}

extension Result {
    public var urlError: URLError? {
        return error as? URLError
    }
    
    public var wasCancelled: Bool {
        return urlError?.code == .cancelled
    }
    
    @discardableResult
    public func onSuccess(block: (Value)->()) -> Result {
        if let value = value {
            block(value)
        }
        return self
    }
    
    @discardableResult
    public func onError(block: (Error)->()) -> Result {
        if !wasCancelled, let error = error {
            block(error)
        }
        return self
    }
}