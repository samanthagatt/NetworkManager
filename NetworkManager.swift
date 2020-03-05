//
//  NetworkManager.swift
//
//  Created by Samantha Gatt on 6/17/19.
//  Copyright © 2019 Samantha Gatt. All rights reserved.
//

import Foundation

class NetworkManager {
    /// Default network manager with no unique configurations
    let shared = NetworkManager()
    
    /// Session used for all network calls
    private var session: URLSession
    
    init(headers: [String: String] = [:], session: URLSession = URLSession.shared) {
        
        self.session = session
        session.configuration.httpAdditionalHeaders = headers
    }
    
    /// HTTP Methods
    enum Method: String {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
        case delete = "DELETE"
    }
    
    /// Common errors found while trying to execute network requests
    enum NetworkError: Error {
        case constructingURLFailed
        case noDataReturned
        case noNetworkResponse
        case decodingDataFailed(error: Error)
        case dataTaskError(error: NSError)
        case responseError(response: HTTPURLResponse)
    }
    
    /// Constructs a URL from the components passed in
    /// - Parameter baseURLString: The starting url for your network call as a string
    /// - Parameter appendingPaths: An array of the paths to append to the end of the base url in order
    /// - Parameter queries: A dictionary of query keys and values to be appended to the end of the final url
    /// - Returns: The constructed URL as an optional
    static func constructURL(baseURLString: String, appendingPaths: [String] = [], queries: [String: String] = [:]) -> URL? {
        
        // Creates base url from string
        guard var url = URL(string: baseURLString) else { return nil }
        // Appends all paths
        for path in appendingPaths {
            url.appendPathComponent(path)
        }
        // Starts empty query array
        var queryArray = [URLQueryItem]()
        // Creates and adds queries to query array from passed in query dictionary
        for query in queries {
            queryArray.append(URLQueryItem(name: query.key, value: query.value))
        }
        // Converts url into components
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Adds query array to url components
        if queryArray.count > 0 {
            urlComponents?.queryItems = queryArray
        }
        // Returns final constructed url
        return urlComponents?.url
    }
    
    /// Constructs a URLRequest from the parameters passed in
    /// - Parameter method: The desired HTTP method for the request
    /// - Parameter url: The url to send the the request
    /// - Parameter headers: The headers as a dictionary to attach to the request
    /// - Parameter encodedData: The data to attach to the body of the request
    /// - Returns: The constructed URLRequest
    static func constructRequest(method: Method = .get, url: URL, headers: [String: String], encodedData: Data? = nil) -> URLRequest {
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        request.httpBody = encodedData
        return request
    }
    
    /// Performs a network call with the provided request and dispatches back to main thread
    /// - Parameter request: The network request to perform
    /// - Parameter success: Closure that will be run after a successful network call
    /// - Parameter data: The data returned from the network
    /// - Parameter failure: Closure that will be run after a failed network call
    /// - Parameter error: The reason the network request failed as an instance of `NetworkManager.NetworkError` enum
    func dataTask(request: URLRequest, success: @escaping (_ data: Data?) -> Void, failure: @escaping (_ error: NetworkError, _ data: Data?) -> Void) {
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    failure(.dataTaskError(error: error as NSError), data)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    failure(.noNetworkResponse, data)
                    return
                }
                if 200..<300 ~= httpResponse.statusCode {
                    success(data)
                } else {
                    failure(.responseError(response: httpResponse), data)
                }
            }
        }.resume()
    }
    
    /// Performs a network call and decodes data on success
    /// - Parameter request: The network request to perform
    /// - Parameter success: Closure that will be run after a successful network call
    /// - Parameter response: The decoded data returned from the network request
    /// - Parameter failure: Closure that will be run after a failed network call
    /// - Parameter error: The reason the network request failed as an instance of `NetworkManager.NetworkError` enum
    /// - Parameter data: The data returned from the network call
    func genericDataTask<T: Decodable>(request: URLRequest, success: @escaping (_ response: T) -> Void, failure: @escaping (_ error: NetworkError, _ data: Data?) -> Void) {

        dataTask(request: request, success: { (data) in
            guard let data = data else {
                failure(.noDataReturned, nil)
                return
            }
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                success(decodedData)
            } catch {
                failure(.decodingDataFailed(error: error), data)
                return
            }
        }, failure: failure)
    }
    
    /// Performs a network call and decodes data on success
    /// - Parameter request: The network request to perform
    /// - Parameter success: Closure that will be run after a successful network call
    /// - Parameter data: The data returned from the network call
    /// - Parameter failure: Closure that will be run after a failed network call
    /// - Parameter error: The reason the network request failed as an instance of `NetworkManager.NetworkError` enum
    /// - Parameter response: The decoded data returned from the network request
    func dataTaskWithErrorResponse<E: Decodable>(request: URLRequest, success: @escaping (_ data: Data?) -> Void, failure: @escaping (_ error: NetworkError, _ response: E?) -> Void) {
        
        dataTask(request: request, success: success) { (error, data) in
            guard let data = data else { failure(error, nil); return }
            let errorResponse = try? JSONDecoder().decode(E.self, from: data)
            failure(error, errorResponse)
        }
    }
    
    /// Performs a network call and decodes data on success
    /// - Parameter request: The network request to perform
    /// - Parameter success: Closure that will be run after a successful network call
    /// - Parameter response: The decoded data returned from the network request
    /// - Parameter failure: Closure that will be run after a failed network call
    /// - Parameter error: The reason the network request failed as an instance of `NetworkManager.NetworkError` enum
    func genericDataTaskWithErrorResponse<T: Decodable, E: Decodable>(request: URLRequest, success: @escaping (_ response: T) -> Void, failure: @escaping (_ error: NetworkError, _ response: E?) -> Void) {
        
        genericDataTask(request: request, success: success) { (error, data) in
            guard let data = data else { failure(error, nil); return }
            let errorResponse = try? JSONDecoder().decode(E.self, from: data)
            failure(error, errorResponse)
        }
    }
}
