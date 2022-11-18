import Foundation

public extension Session {
    @discardableResult
    func start<C: Call>(call: C,
                        loadWidthCache: Bool,
                        offlineCaching: Bool = true,
                        cachePolicy: NSURLRequest.CachePolicy,
                        completion: @escaping (Result<C.Parser.OutputType>, HttpSource) -> Void) -> URLSessionDataTask {
        let tsk = dataTask(for: call, returnCachedResponse: false, cachePolicy: cachePolicy, completion: completion) // TODO: Make returnCachedResponse
        tsk.resume()
        return tsk
    }
    
#if compiler(>=5.5) && canImport(_Concurrency)
    
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0,  *)
    func start<C: Call>(call: C,
                        loadWidthCache: Bool,
                        offlineCaching: Bool = true,
                        cachePolicy: NSURLRequest.CachePolicy) async throws -> (C.Parser.OutputType, HTTPURLResponse, HttpSource) {
        return try await dataTask(for: call, loadWidthCache: loadWidthCache, offlineCaching: offlineCaching, cachePolicy: cachePolicy)
    }
    
//    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0,  *)
//    func start<C: Call>(call: C) async throws -> (C.Parser.OutputType, HTTPURLResponse, HttpSource) {
//        return try await dataTask(for: call, instantlyReturnCache: false)
//    }
    
//    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0,  *)
//    func cachedResponse<C: Call>(call: C) async throws -> (C.Parser.OutputType, HTTPURLResponse, HttpSource) {
//        return try await dataTask(for: call, instantlyReturnCache: true)
//    }

#endif
    
}
