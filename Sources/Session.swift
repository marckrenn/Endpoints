import Foundation

public struct Result<Value> {
    public var value: Value?
    public var error: Error?
    
    public let response: HTTPURLResponse?
    
    public init(response: HTTPURLResponse?) {
        self.response = response
    }
}

public enum HTTPSource {
    case none
    case origin
    case cache
}

public struct HTTPResult<C: Call> {
    public init(value: C.Parser.OutputType, response: HTTPURLResponse, source: HTTPSource) {
        self.value = value
        self.response = response
        self.source = source
    }
    
    public let value: C.Parser.OutputType
    public let response: HTTPURLResponse
    public let source: HTTPSource
}

public enum HTTPError<C: Call>: Error {
    case noResponse
    case noResponseNoCache
    case noResponseWithCache((HTTPResult<C>, Error))
}

public class Session<C: Client> {
    public var debug = false
    
    public var urlSession: URLSession
    public let client: C
    
    public init(with client: C, using urlSession: URLSession = URLSession.shared) {
        self.client = client
        self.urlSession = urlSession
    }
    
    public func dataTask<C: Call>(for call: C,
                                  returnCachedResponse: Bool,
                                  cachePolicy: NSURLRequest.CachePolicy,
                                  completion: @escaping (Result<C.Parser.OutputType>, HTTPSource) -> Void) -> URLSessionDataTask {
        
        var urlRequest = client.encode(call: call)
        
        urlRequest.cachePolicy = returnCachedResponse && self.urlSession.configuration.urlCache?.cachedResponse(for: urlRequest) != nil ? .returnCacheDataDontLoad : cachePolicy
        
        weak var tsk: URLSessionDataTask?
        let task = urlSession.dataTask(with: urlRequest) { data, response, error in
            let sessionResult = URLSessionTaskResult(response: response, data: data, error: error)
            
            if let tsk = tsk, self.debug {
                //                print("\(tsk.requestDescription)\n\(sessionResult)")
            }
            
            let result = self.transform(sessionResult: sessionResult, for: call)
            
            if returnCachedResponse,
               let urlCache = self.urlSession.configuration.urlCache,
               let cachedResponse = urlCache.cachedResponse(for: urlRequest),
               let httpResponse = cachedResponse.response as? HTTPURLResponse {
                
                let sessionResult = URLSessionTaskResult(response: httpResponse, data: data, error: error)
                let result = self.transform(sessionResult: sessionResult, for: call)
                
                DispatchQueue.main.async {
                    completion(result, .cache)
                }
                
            } else {
                
                DispatchQueue.main.async {
                    completion(result, .origin)
                }
                
            }
            
        }

        tsk = task // Keep a weak reference for debug output
        
        return task
    }
    
#if compiler(>=5.5) && canImport(_Concurrency)
    
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0,  *)
    public func dataTask<C: Call>(for call: C,
                                  loadWidthCache: Bool,
                                  offlineCaching: Bool,
                                  cachePolicy: NSURLRequest.CachePolicy) async throws -> (C.Parser.OutputType, HTTPURLResponse, HTTPSource) {
        var cancelledBeforeStart = false
        var task: URLSessionDataTask?
        var taskCache: URLSessionDataTask?
        
        let cancelTask = {
            cancelledBeforeStart = true
            task?.cancel()
        }
        
        let result = try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<HTTPResult<C>, Error>) in
                    if cancelledBeforeStart {
                        return
                    }
                    
                    task = dataTask(for: call,
                                    returnCachedResponse: loadWidthCache,
                                    cachePolicy: cachePolicy,
                                    completion: { result, source in
                        
                        result.onSuccess { response in
                            guard let response = result.response,
                                  let body = result.value
                            else {
                                continuation.resume(throwing: HTTPError<C>.noResponse)
                                return
                            }
                            
                            continuation.resume(returning: HTTPResult(value: body, response: response, source: source))
                            
                        }.onError { error in
                            
                            if offlineCaching {
                                
                                // Return cached response if available
                                taskCache = self.dataTask(for: call,
                                                          returnCachedResponse: true,
                                                          cachePolicy: cachePolicy,
                                                          completion: { result, source in
                                    result.onSuccess { response in
                                        guard let response = result.response,
                                              let body = result.value
                                        else {
                                            continuation.resume(throwing: HTTPError<C>.noResponseNoCache)
                                            return
                                        }
                                        
                                        //                                        continuation.resume(returning: HttpResult(value: body, response: response, source: source))
                                        continuation.resume(throwing: HTTPError<C>.noResponseWithCache((HTTPResult<C>(value: body, response: response, source: source), error)))
                                        
                                    }.onError { _ in
                                        
                                        continuation.resume(throwing: HTTPError<C>.noResponseNoCache)
                                        
                                    }
                                })
                                
                                taskCache?.resume()
                                
                            } else {
                                continuation.resume(throwing: HTTPError<C>.noResponse)
                            }
                            
                        }
                    })
                    
                    task?.resume()
                })
            }, onCancel: {
                cancelTask()
            }
        )
        
        return (result.value, result.response, result.source)
    }

#endif
    
    func transform<C: Call>(sessionResult: URLSessionTaskResult, for call: C) -> Result<C.Parser.OutputType> {
        var result = Result<C.Parser.OutputType>(response: sessionResult.httpResponse)
        
        do {
            result.value = try client.parse(sessionTaskResult: sessionResult, for: call)
        } catch {
            result.error = error
        }
        
        return result
    }
}
