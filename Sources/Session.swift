import Foundation

public struct Result<Value> {
    public var value: Value?
    public var error: Error?
    
    public let response: HTTPURLResponse?
    
    public init(response: HTTPURLResponse?) {
        self.response = response
    }
}

public enum HttpSource {
    case none
    case origin
    case cache
}

public struct HttpResult<C: Call> {
    public let value: C.Parser.OutputType
    public let response: HTTPURLResponse
    public let source: HttpSource
}

public enum HttpError<C: Call>: Error {
    case NoResponse
    case NoResponseNoCache
    case NoResponseWithCache((HttpResult<C>, Error))
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
                                  completion: @escaping (Result<C.Parser.OutputType>, HttpSource) -> Void) -> URLSessionDataTask {
        
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
                                  cachePolicy: NSURLRequest.CachePolicy) async throws -> (C.Parser.OutputType, HTTPURLResponse, HttpSource) {
        var cancelledBeforeStart = false
        var task: URLSessionDataTask?
        var taskCache: URLSessionDataTask?
        
        let cancelTask = {
            cancelledBeforeStart = true
            task?.cancel()
        }
        
        let result = try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<HttpResult<C>, Error>) in
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
                                continuation.resume(throwing: HttpError<C>.NoResponse)
                                return
                            }
                            
                            continuation.resume(returning: HttpResult(value: body, response: response, source: source))
                            
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
                                            continuation.resume(throwing: HttpError<C>.NoResponseNoCache)
                                            return
                                        }
                                        
                                        //                                        continuation.resume(returning: HttpResult(value: body, response: response, source: source))
                                        continuation.resume(throwing: HttpError<C>.NoResponseWithCache((HttpResult<C>(value: body, response: response, source: source), error)))
                                        
                                    }.onError { _ in
                                        
                                        continuation.resume(throwing: HttpError<C>.NoResponseNoCache)
                                        
                                    }
                                })
                                
                                taskCache?.resume()
                                
                            } else {
                                continuation.resume(throwing: HttpError<C>.NoResponse)
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
    
//    public struct HttpResult<C: Call> {
//        let value: C.Parser.OutputType
//        let response: HTTPURLResponse
//        let source: HttpSource
//    }
    
//    public enum HttpError<C: Call>: Error {
//        case NoResponse
//        case NoResponseNoCache
//        case NoResponseWithCache(HttpResult<C>, Error)
//    }
    
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
