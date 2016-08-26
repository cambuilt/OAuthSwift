//
//  OAuthSwiftHTTPRequest.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 6/21/14.
//  Copyright (c) 2014 Dongri Jin. All rights reserved.
//

import Foundation
import UIKit

let kHTTPHeaderContentType = "Content-Type"

public class OAuthSwiftHTTPRequest: NSObject, URLSessionDelegate, OAuthSwiftRequestHandle {
    
    public typealias SuccessHandler = (_ data: Data, _ response: HTTPURLResponse) -> Void
    public typealias FailureHandler = (_ error: NSError) -> Void
    
    // HTTP request method
    // https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Request_methods
    public enum Method: String {
        case GET, POST, PUT, DELETE, PATCH, HEAD //, OPTIONS, TRACE, CONNECT
        
        var isBody: Bool {
            return self == .POST || self == .PUT || self == .PATCH
        }
    }
    
    // Where the additional parameters will be injected
    @objc public enum ParamsLocation : Int {
        case AuthorizationHeader, /*FormEncodedBody,*/ RequestURIQuery
    }
    
    // Configuration for request
    public struct Config {
        
        // NSURLRequest (url, method, ...)
        public var urlRequest:URLRequest   // TODO make this not mutable (ie. do not allow to modify header after...
        /// These parameters are either added to the query string for GET, HEAD and DELETE requests or
        /// used as the http body in case of POST, PUT or PATCH requests.
        ///
        /// If used in the body they are either encoded as JSON or as encoded plaintext based on the Content-Type header field.
        public var parameters: [String: Any]
        public let paramsLocation: ParamsLocation
        public let dataEncoding: String.Encoding
        
        public var HTTPMethod: Method {
            let requestMethod = urlRequest.httpMethod!
            return Method(rawValue: requestMethod) ?? .GET
        }
        
        public var URL: URL? {
            return urlRequest.url
        }
        
        public var charset: CFString {
            return CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(self.dataEncoding.rawValue))
        }
        
        public init(url: URL, HTTPMethod: String = "GET", HTTPBody: Data? = nil, headers: [String: String] = [:], timeoutInterval: TimeInterval = 60
            , HTTPShouldHandleCookies: Bool = false, parameters: [String: Any], paramsLocation: ParamsLocation = .AuthorizationHeader, dataEncoding: String.Encoding = OAuthSwiftDataEncoding) {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = HTTPMethod
            urlRequest.httpBody = HTTPBody
            urlRequest.allHTTPHeaderFields = headers
            urlRequest.timeoutInterval = timeoutInterval
            urlRequest.httpShouldHandleCookies = HTTPShouldHandleCookies
            self.init(urlRequest: urlRequest, parameters: parameters, paramsLocation: paramsLocation, dataEncoding: dataEncoding)
        }
        
        public init(urlRequest: URLRequest, parameters: [String: Any] = [:], paramsLocation: ParamsLocation = .AuthorizationHeader, dataEncoding: String.Encoding = OAuthSwiftDataEncoding) {
            self.urlRequest = urlRequest
            self.parameters = parameters
            self.paramsLocation = paramsLocation
            self.dataEncoding = dataEncoding
        }
    }
    public private(set) var config: Config
    
    
    private var request: URLRequest?
    private var task: URLSessionTask?
    private var session: URLSession!
    
    private var cancelRequested = false
    
    var successHandler: SuccessHandler?
    var failureHandler: FailureHandler?
    
    // MARK: INIT
    
    convenience init(URL: URL, method: String = "GET", parameters: [String: Any] = [:], paramsLocation : ParamsLocation = .AuthorizationHeader, HTTPBody: Data? = nil, headers: [String: String] = [:]) {
        self.init(config: Config(url: URL, HTTPMethod: method, HTTPBody: HTTPBody, headers: headers, parameters: parameters, paramsLocation: paramsLocation))
    }
    
    convenience init(request: URLRequest, paramsLocation : ParamsLocation = .AuthorizationHeader) {
        self.init(config: Config(urlRequest: request, paramsLocation: paramsLocation))
    }
    
    init(config: Config) {
        self.config = config
    }
    
    func start() {
        guard request == nil else { return } // Don't start the same request twice!
        
        do {
            self.request = try self.makeRequest()
        } catch let error as NSError {
            failureHandler?(NSError(domain: OAuthSwiftErrorDomain, code: OAuthSwiftErrorCode.requestCreationError.rawValue, userInfo: [
                NSLocalizedDescriptionKey: error.localizedDescription,
                NSUnderlyingErrorKey: error
                ])
            )
            self.request = nil
            return
        }
        
        DispatchQueue.main.async {
            // perform lock here to prevent cancel calls on another thread while creating the request
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            if self.cancelRequested {
                return
            }
            
            self.session = URLSession(configuration: URLSessionConfiguration.default,
                                        delegate: self,
                                        delegateQueue: OperationQueue.main)
            self.task = self.session.dataTask(with: self.request!) { [unowned self] data, response, error -> Void in
                #if os(iOS)
                    #if !OAUTH_APP_EXTENSIONS
                        UIApplication.shared.isNetworkActivityIndicatorVisible = false
                    #endif
                #endif
                
                guard error == nil else {
                    self.failureHandler?(error! as NSError)
                    return
                }
                
                guard let response = response as? HTTPURLResponse, let responseData = data else {
                    let badRequestCode = 400
                    let localizedDescription = OAuthSwiftHTTPRequest.descriptionForHTTPStatus(status: badRequestCode, responseString: "")
                    let userInfo : [NSObject : Any] = [NSLocalizedDescriptionKey as NSObject: localizedDescription]
                    let error = NSError(domain: NSURLErrorDomain, code: badRequestCode, userInfo: userInfo)
                    self.failureHandler?(error)
                    return
                }
                
                guard response.statusCode < 400 else {
                    var errorCode = response.statusCode
                    var localizedDescription = String()
                    let responseString = String(data: responseData, encoding: self.config.dataEncoding)
                    
                    if let responseJSON = try? JSONSerialization.jsonObject(with: responseData, options: .mutableContainers) as? NSDictionary {
                        if let code = responseJSON!["error"] as? String, let description = responseJSON!["error_description"] as? String {
                            localizedDescription = NSLocalizedString("\(code) \(description)", comment: "")
                            if code == "authorization_pending" {
                                errorCode = OAuthSwiftErrorCode.authorizationPending.rawValue
                            }
                        }
                    } else {
                        localizedDescription = OAuthSwiftHTTPRequest.descriptionForHTTPStatus(status: response.statusCode, responseString: String(data: responseData, encoding: self.config.dataEncoding)!)
                    }
                    
                    let userInfo = [
                        NSLocalizedDescriptionKey: localizedDescription,
                        "Response-Headers": response.allHeaderFields,
                        "Response-Body": responseString,
                        NSURLErrorFailingURLErrorKey: response.url?.absoluteString,
                        OAuthSwiftErrorResponseKey: response,
                        OAuthSwiftErrorResponseDataKey: responseData
                    ] as [String:Any]
                    
                    let error = NSError(domain: NSURLErrorDomain, code: errorCode, userInfo: userInfo)
                    self.failureHandler?(error)
                    return
                }
                
                self.successHandler?(responseData, response)
            }
            self.task?.resume()
            self.session.finishTasksAndInvalidate()
            
            #if os(iOS)
                #if !OAUTH_APP_EXTENSIONS
                    UIApplication.shared.isNetworkActivityIndicatorVisible = true
                #endif
            #endif
        }
    }
    
    public func cancel() {
        // perform lock here to prevent cancel calls on another thread while creating the request
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        // either cancel the request if it's already running or set the flag to prohibit creation of the request
        if let task = task {
            task.cancel()
        } else {
            cancelRequested = true
        }
    }
    
    public func makeRequest() throws -> URLRequest {
        return try OAuthSwiftHTTPRequest.makeRequest(config: config)
    }
    
    public class func makeRequest(config: Config)  throws -> URLRequest  {
        return try setupRequestForOAuth(request: config.urlRequest,
                                        headers: [:], // request.allHTTPHeaderFields (useless already in request, keep compatibility)
            parameters: config.parameters,
            dataEncoding: config.dataEncoding,
            body: nil, // config.body (useless already in request, keep compatibility)
            paramsLocation: config.paramsLocation
        )
    }
    
    public class func makeRequest(
        url: URL,
        method: Method,
        headers: [String : String],
        parameters: Dictionary<String, Any>,
        dataEncoding: String.Encoding,
        body: Data? = nil,
        paramsLocation: ParamsLocation = .AuthorizationHeader) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        return try setupRequestForOAuth(request: request,
                                        headers: headers,
                                        parameters: parameters,
                                        dataEncoding: dataEncoding,
                                        body: body,
                                        paramsLocation: paramsLocation
        )
        
    }
    
    public class func setupRequestForOAuth(request: URLRequest,
                                           headers: [String : String] = [:],
                                           parameters: [String: Any],
                                           dataEncoding: String.Encoding,
                                           body: Data? = nil,
                                           paramsLocation : ParamsLocation = .AuthorizationHeader) throws -> URLRequest {
        var req = request
        
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        let finalHeaders = request.allHTTPHeaderFields ?? [:]
        
        let charset = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(dataEncoding.rawValue))
        
        let finalParameters : [String: Any]
        switch (paramsLocation) {
        case .AuthorizationHeader:
            finalParameters = parameters.filter { key, _ in !key.hasPrefix("oauth_") }
        case .RequestURIQuery:
            finalParameters = parameters
        }
        
        if let b = body {
            req.httpBody = b
        } else {
            if finalParameters.count > 0 {
                if request.httpMethod == "GET" || request.httpMethod == "HEAD" || request.httpMethod == "DELETE" {
                    let queryString = finalParameters.urlEncodedQueryStringWithEncoding(dataEncoding)
                    let URL = request.url!
                    req.url = URL.URLByAppendingQueryString(queryString)
                    if finalHeaders[kHTTPHeaderContentType] == nil {
                        req.setValue("application/x-www-form-urlencoded; charset=\(charset)", forHTTPHeaderField: kHTTPHeaderContentType)
                    }
                }
                else {
                    if let contentType = finalHeaders[kHTTPHeaderContentType], contentType.contains("application/json") == true {
                        let jsonData = try JSONSerialization.data(withJSONObject: finalParameters, options: [])
                        req.setValue("application/json; charset=\(charset)", forHTTPHeaderField: kHTTPHeaderContentType)
                        req.httpBody = jsonData as Data
                    }
                    else {
                        req.setValue("application/x-www-form-urlencoded; charset=\(charset)", forHTTPHeaderField: kHTTPHeaderContentType)
                        let queryString = finalParameters.urlEncodedQueryStringWithEncoding(dataEncoding)
                        req.httpBody = queryString.data(using: .utf8, allowLossyConversion: true)
                    }
                }
            }
        }
        return req
    }
    
    func makeOAuthSwiftHTTPRequest(credential: OAuthSwiftCredential) {
        let method = self.config.HTTPMethod
        let url = self.config.urlRequest.url!
        let paramsLocation = self.config.paramsLocation
        let parameters = self.config.parameters
        
        var signatureUrl = url
        var signatureParameters = parameters
        
        // Check if body must be hashed (oauth1)
        let body:Data? = nil
        if method.isBody {
            if let headers = self.config.urlRequest.allHTTPHeaderFields, let contentType = headers[kHTTPHeaderContentType] {
                if contentType.lowercased().contains("application/json") == true {
                    // TODO: oauth_body_hash create body before signing if implementing body hashing
                    /*do {
                     let jsonData: NSData = try NSJSONSerialization.dataWithJSONObject(parameters, options: [])
                     request.HTTPBody = jsonData
                     requestHeaders["Content-Length"] = "\(jsonData.length)"
                     body = jsonData
                     }
                     catch {
                     }*/
                    
                    signatureParameters = [:] // parameters are not used for general signature (could only be used for body hashing
                }
                // else other type are not supported, see setupRequestForOAuth()
            }
        }
        
        // Need to account for the fact that some consumers will have additional parameters on the
        // querystring, including in the case of fetching a request token. Especially in the case of
        // additional parameters on the request, authorize, or access token exchanges, we need to
        // normalize the URL and add to the parametes collection.
        
        var queryStringParameters = [String: Any]()
        let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false )
        if let queryItems = urlComponents?.queryItems {
            for queryItem in queryItems {
                let value = queryItem.value?.safeStringByRemovingPercentEncoding ?? ""
                queryStringParameters.updateValue(value, forKey: queryItem.name)
            }
        }
        
        // According to the OAuth1.0a spec, the url used for signing is ONLY scheme, path, and query
        if queryStringParameters.count>0 {
            urlComponents?.query = nil
            // This is safe to unwrap because these just came from an NSURL
            signatureUrl = urlComponents?.url ?? url
        }
        signatureParameters = signatureParameters.join(queryStringParameters)
        
        var requestHeaders = [String:String]()
        switch paramsLocation {
        case .AuthorizationHeader:
            //Add oauth parameters in the Authorization header
            requestHeaders += credential.makeHeaders(signatureUrl, method: method.rawValue, parameters: signatureParameters as Dictionary<String, AnyObject>, body: body)
        case .RequestURIQuery:
            //Add oauth parameters as request parameters
            self.config.parameters += credential.authorizationParametersWithSignatureForMethod(method.rawValue, url: signatureUrl, parameters: signatureParameters, body: body)
        }
        
        if let headers = self.config.urlRequest.allHTTPHeaderFields {
            self.config.urlRequest.allHTTPHeaderFields = requestHeaders + headers
        }
    }
    
}

// MARK: status code mapping

extension OAuthSwiftHTTPRequest {
    
    public class func descriptionForHTTPStatus(status: Int, responseString: String) -> String {
        var s = "HTTP Status \(status)"
        
        var description: String?
        // http://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
        if status == 400 { description = "Bad Request" }
        if status == 401 { description = "Unauthorized" }
        if status == 402 { description = "Payment Required" }
        if status == 403 { description = "Forbidden" }
        if status == 404 { description = "Not Found" }
        if status == 405 { description = "Method Not Allowed" }
        if status == 406 { description = "Not Acceptable" }
        if status == 407 { description = "Proxy Authentication Required" }
        if status == 408 { description = "Request Timeout" }
        if status == 409 { description = "Conflict" }
        if status == 410 { description = "Gone" }
        if status == 411 { description = "Length Required" }
        if status == 412 { description = "Precondition Failed" }
        if status == 413 { description = "Payload Too Large" }
        if status == 414 { description = "URI Too Long" }
        if status == 415 { description = "Unsupported Media Type" }
        if status == 416 { description = "Requested Range Not Satisfiable" }
        if status == 417 { description = "Expectation Failed" }
        if status == 422 { description = "Unprocessable Entity" }
        if status == 423 { description = "Locked" }
        if status == 424 { description = "Failed Dependency" }
        if status == 425 { description = "Unassigned" }
        if status == 426 { description = "Upgrade Required" }
        if status == 427 { description = "Unassigned" }
        if status == 428 { description = "Precondition Required" }
        if status == 429 { description = "Too Many Requests" }
        if status == 430 { description = "Unassigned" }
        if status == 431 { description = "Request Header Fields Too Large" }
        if status == 432 { description = "Unassigned" }
        if status == 500 { description = "Internal Server Error" }
        if status == 501 { description = "Not Implemented" }
        if status == 502 { description = "Bad Gateway" }
        if status == 503 { description = "Service Unavailable" }
        if status == 504 { description = "Gateway Timeout" }
        if status == 505 { description = "HTTP Version Not Supported" }
        if status == 506 { description = "Variant Also Negotiates" }
        if status == 507 { description = "Insufficient Storage" }
        if status == 508 { description = "Loop Detected" }
        if status == 509 { description = "Unassigned" }
        if status == 510 { description = "Not Extended" }
        if status == 511 { description = "Network Authentication Required" }
        
        if (description != nil) {
            s = s + ": " + description! + ", Response: " + responseString
        }
        
        return s
    }
    
}
