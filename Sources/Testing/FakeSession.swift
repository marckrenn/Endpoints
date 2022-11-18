import Foundation

public class FakeSession<C: Client>: Session<C> {
    var resultProvider: FakeResultProvider

    public init(with client: C, resultProvider: FakeResultProvider) {
        self.resultProvider = resultProvider

        super.init(with: client)
    }

    override public func dataTask<C : Call>(for call: C,
                                            returnCachedResponse: Bool,
                                            cachePolicy: NSURLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
                                            completion: @escaping (Result<C.Parser.OutputType>, HttpSource) -> Void) -> URLSessionDataTask {
        return FakeURLSessionDataTask {
            DispatchQueue.global().async {
                let sessionResult = self.resultProvider.resultFor(call: call)

                if self.debug {
                    print("\(call.request.cURLRepresentation)\n\(sessionResult)")
                }

                let result = self.transform(sessionResult: sessionResult, for: call)

                DispatchQueue.main.async {
                    completion(result, .none)
                }
            }
        }
    }
}
