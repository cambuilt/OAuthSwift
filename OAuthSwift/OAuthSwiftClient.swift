//
//  OAuthSwiftClient.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 6/21/14.
//  Copyright (c) 2014 Dongri Jin. All rights reserved.
//

import Foundation

var OAuthSwiftDataEncoding: String.Encoding = String.Encoding.utf8

public protocol OAuthSwiftRequestHandle {
    func cancel()
}

open class OAuthSwiftClient: NSObject {

    fileprivate(set) open var credential: OAuthSwiftCredential
    open var paramsLocation: OAuthSwiftHTTPRequest.ParamsLocation = .AuthorizationHeader

    static let separator: String = "\r\n"
    static var separatorData: Data = {
        return OAuthSwiftClient.separator.data(using: OAuthSwiftDataEncoding)!
    }()

    // MARK: init
    public init(consumerKey: String, consumerSecret: String) {
        self.credential = OAuthSwiftCredential(consumer_key: consumerKey, consumer_secret: consumerSecret)
    }
    
    public init(consumerKey: String, consumerSecret: String, accessToken: String, accessTokenSecret: String) {
        self.credential = OAuthSwiftCredential(oauth_token: accessToken, oauth_token_secret: accessTokenSecret)
        self.credential.consumer_key = consumerKey
        self.credential.consumer_secret = consumerSecret
    }
    
    public init(credential: OAuthSwiftCredential) {
        self.credential = credential
    }

    // MARK: client methods
    open func get(_ urlString: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        return self.request(urlString, method: "GET", parameters: parameters, headers: headers, success: success, failure: failure)
    }
    
    open func post(_ urlString: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        return self.request(urlString, method: "POST", parameters: parameters, headers: headers, success: success, failure: failure)
    }

    open func put(_ urlString: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, body: Data? = nil, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        return self.request(urlString, method: "PUT", parameters: parameters, headers: headers, body: body, success: success, failure: failure)
    }

    open func delete(_ urlString: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        return self.request(urlString, method: "DELETE", parameters: parameters, headers: headers,success: success, failure: failure)
    }

    open func patch(_ urlString: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        return self.request(urlString, method: "PATCH", parameters: parameters, headers: headers,success: success, failure: failure)
    }
    
    open func request(_ urlString: String, method: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, body: Data? = nil, checkTokenExpiration: Bool = true, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) -> OAuthSwiftRequestHandle? {
        
        if checkTokenExpiration && self.credential.isTokenExpired()  {
            let errorInfo = [NSLocalizedDescriptionKey: NSLocalizedString("The provided token is expired.", comment:"Token expired, retrieve new token by using the refresh token")]
            
            if let failureHandler = failure {
                failureHandler(NSError(domain: OAuthSwiftErrorDomain, code: OAuthSwiftErrorCode.tokenExpiredError.rawValue, userInfo: errorInfo))
            }
            
            return nil
        }

        guard let _ = URL(string: urlString) else {
            failure?(NSError(domain: OAuthSwiftErrorDomain, code: OAuthSwiftErrorCode.requestCreationError.rawValue, userInfo: nil))
            return nil
        }

        if let request = makeRequest(urlString, method: method, parameters: parameters, headers: headers, body: body) {
            request.successHandler = success
            request.failureHandler = failure
            request.start()
            return request
        }
        return nil
    }
    
    open func makeRequest(_ request: URLRequest) -> OAuthSwiftHTTPRequest {
        let request = OAuthSwiftHTTPRequest(request:request, paramsLocation: self.paramsLocation)
        request.makeOAuthSwiftHTTPRequest(credential: self.credential)
        return request
    }

    open func makeRequest(_ urlString: String, method: String, parameters: [String: Any] = [:], headers: [String:String]? = nil, body: Data? = nil) -> OAuthSwiftHTTPRequest? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        let request = OAuthSwiftHTTPRequest(URL: url, method: method, parameters: parameters, paramsLocation: self.paramsLocation, HTTPBody: body, headers: headers ?? [:])
        request.makeOAuthSwiftHTTPRequest(credential: self.credential)
        return request
    }

    @available(*, deprecated: 0.6.0, message: "This method will be removed to make OAuthSwiftHTTPRequest.Config not mutable")
    open func makeOAuthSwiftHTTPRequest(_ request: OAuthSwiftHTTPRequest) -> OAuthSwiftHTTPRequest {
        request.makeOAuthSwiftHTTPRequest(credential: self.credential)
        return request
    }

    open func postImage(_ urlString: String, parameters: [String:Any], image: Data, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?)  -> OAuthSwiftRequestHandle? {
        return self.multiPartRequest(urlString, method: "POST", parameters: parameters, image: image, success: success, failure: failure)
    }

    func multiPartRequest(_ url: String, method: String, parameters: [String:Any], image: Data, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?)  -> OAuthSwiftRequestHandle? {
        
        let paramImage: [String: AnyObject] = ["media": image as AnyObject]
        let boundary = "AS-boundary-\(arc4random())-\(arc4random())"
        let type = "multipart/form-data; boundary=\(boundary)"
        let body = self.multiPartBodyFromParams(paramImage, boundary: boundary)
        let headers = [kHTTPHeaderContentType: type]

        if let request = makeRequest(url, method: method, parameters: parameters, headers: headers, body: body) { // TODO check if headers do not override others...

            request.successHandler = success
            request.failureHandler = failure
            request.start()
            return request
        }
        return nil
    }

    open func multiPartBodyFromParams(_ parameters: [String: AnyObject], boundary: String) -> Data {
        let data = NSMutableData()

        let prefixString = "--\(boundary)\r\n"
        let prefixData = prefixString.data(using: OAuthSwiftDataEncoding)!

        
        for (key, value) in parameters {
            var sectionData: Data
            var sectionType: String?
            var sectionFilename: String?
            if  let multiData = value as? Data , key == "media" {
                sectionData = multiData
                sectionType = "image/jpeg"
                sectionFilename = "file"
            } else {
                sectionData = "\(value)".data(using: OAuthSwiftDataEncoding)!
            }

            data.append(prefixData)
            let multipartData = OAuthSwiftMultipartData(name: key, data: (sectionData as NSData) as Data, fileName: sectionFilename, mimeType: sectionType)
            data.appendMultipartData(multipartData, encoding: OAuthSwiftDataEncoding, separatorData: OAuthSwiftClient.separatorData)
        }

        let endingString = "--\(boundary)--\r\n"
        let endingData = endingString.data(using: OAuthSwiftDataEncoding)!
        data.append(endingData)
        return data as Data
    }
    
    open func postMultiPartRequest(_ url: String, method: String, parameters: [String:Any], headers: [String: String]? = nil, multiparts: Array<OAuthSwiftMultipartData> = [], checkTokenExpiration: Bool = true, success: OAuthSwiftHTTPRequest.SuccessHandler?, failure: OAuthSwiftHTTPRequest.FailureHandler?) {
        
        let boundary = "POST-boundary-\(arc4random())-\(arc4random())"
        let type = "multipart/form-data; boundary=\(boundary)"
        let body = self.multiDataFromObject(parameters, multiparts: multiparts, boundary: boundary)
        
        var finalHeaders = [kHTTPHeaderContentType: type]
        finalHeaders += headers ?? [:]
        
        if let request = makeRequest(url, method: method, parameters: parameters, headers: finalHeaders, body: body) { // TODO check if headers do not override 
            request.successHandler = success
            request.failureHandler = failure
            request.start()
        }
    }

    func multiDataFromObject(_ object: [String:Any], multiparts: Array<OAuthSwiftMultipartData>, boundary: String) -> Data? {
        let data = NSMutableData()

        let prefixString = "--\(boundary)\r\n"
        let prefixData = prefixString.data(using: OAuthSwiftDataEncoding)!

        for (key, value) in object {
            guard let valueData = "\(value)".data(using: OAuthSwiftDataEncoding) else {
                continue
            }
            data.append(prefixData)
            let multipartData = OAuthSwiftMultipartData(name: key, data: (valueData as NSData) as Data, fileName: nil, mimeType: nil)
            data.appendMultipartData(multipartData, encoding: OAuthSwiftDataEncoding, separatorData: OAuthSwiftClient.separatorData)
        }

        for multipart in multiparts {
            data.append(prefixData)
            data.appendMultipartData(multipart, encoding: OAuthSwiftDataEncoding, separatorData: OAuthSwiftClient.separatorData)
        }

        let endingString = "--\(boundary)--\r\n"
        let endingData = endingString.data(using: OAuthSwiftDataEncoding)!
        data.append(endingData)

        return data as Data
    }

}
