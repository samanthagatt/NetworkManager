//
//  NetworkManager.swift
//
//  Created by Samantha Gatt on 6/17/19.
//  Copyright © 2019 Samantha Gatt. All rights reserved.
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

enum NetworkCompletion<T, E> {
    case success(response: T)
    case failure(response: E?, error: NetworkError)
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

class NetworkManager {
    /// Default network manager with no unique configurations
    static let shared = NetworkManager()
    
    /// Session used for all network calls
    private let session: URLSession
    
    init(headers: [String: String] = [:], session: URLSession = URLSession.shared) {
        self.session = session
        session.configuration.httpAdditionalHeaders = headers
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
    
    /// Percent escapes the provided string
    /// - Parameter string: The string to be percent escaped
    /// - Returns: The percent escaped string
    private static func percentEscape(_ string: String) -> String? {
        var characterSet: CharacterSet = .alphanumerics
        characterSet.insert(charactersIn: "-._* ")
        return string
            .addingPercentEncoding(withAllowedCharacters: characterSet)?
            .replacingOccurrences(of: " ", with: "+")
    }
    
    /// Percent escapes and form encodes the provided dictionary
    /// - Parameter parameters: The parameters to be form encoded
    /// - Returns: The form encoded parameters
    /// to be used in network request body
    static func formEncode(_ parameters: [String : String]) -> Data? {
        let parameterArray = parameters.compactMap { (key, value) -> String? in
            guard let escapedValue = Self.percentEscape(value) else { return nil }
            return "\(key)=\(escapedValue)"
        }
        return parameterArray.joined(separator: "&").data(using: .utf8)
    }
    
    /// Constructs a URLRequest from the parameters passed in
    /// - Parameter method: The desired HTTP method for the request
    /// - Parameter url: The url to send the the request
    /// - Parameter headers: The headers as a dictionary to attach to the request
    /// - Parameter encodedData: The data to attach to the body of the request
    /// - Returns: The constructed URLRequest
    static func constructRequest(method: HTTPMethod = .get, url: URL, headers: [String: String] = [:], encodedData: Data? = nil) -> URLRequest {
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        request.httpBody = encodedData
        return request
    }
    
    /// Performs a network call and
    /// decodes data into generic decodable types T and E
    /// (T on success and E on failure)
    ///
    /// If no data is expected to be returned, declare success closure's parameter as type `Data`
    ///
    /// - Parameter request: The network request to perform
    /// - Parameter decoder: Used to decode data returned from network call .
    /// Defaults to a new instance of `JSONDecoder`.
    ///
    /// - Returns: The data task that was performed as a discardable result
    @discardableResult
    func makeRequest<T: Decodable, E: Decodable>(request: URLRequest, decoder: JSONDecoder = JSONDecoder(), completion: @escaping (NetworkCompletion<T, E>) -> Void) -> URLSessionDataTask {
        // Makes data task
        let dataTask = session.dataTask(with: request) { data, response, error in
            // Decodes data from network call into E if E is not Data
            // So it can be passed into failure closure
            let errorResponse = E.self is Data.Type ?
                data as? E :
                try? decoder.decode(E.self, from: data ?? Data())
            
            // Immediately dispatches back to main queue
            // So UI can be safely updated in success and failure closures
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(response: errorResponse, error: .dataTaskError(error: error as NSError)))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(response: errorResponse, error: .noNetworkResponse))
                    return
                }
                if 200..<300 ~= httpResponse.statusCode {
                    // If T is Data
                    // Don't need to decode returned data
                    if T.self is Data.Type {
                        // If data is returned from network call
                        if let tData = data as? T {
                            completion(.success(response: tData))
                            return
                        }
                        // In case no data is expected to be returned from network call
                        // Avoids having to make success parameter optional
                        // Will never fail so failure isn't called
                        guard let noData = Data() as? T else { return }
                        completion(.success(response: noData))
                        return
                    }
                    // If T is not Data
                    // Data is expected to be returned from network call
                    // So calls failure if data is nil
                    guard let data = data else {
                        completion(.failure(response: errorResponse, error: .noDataReturned))
                        return
                    }
                    // Decode data into T
                    do {
                        let decodedData = try decoder.decode(T.self, from: data)
                        completion(.success(response: decodedData))
                    } catch {
                        completion(.failure(response: errorResponse, error: .decodingDataFailed(error: error)))
                        return
                    }
                // Response code is not in the 200s
                } else {
                    completion(.failure(response: errorResponse, error: .responseError(response: httpResponse)))
                }
            }
        }
        // Performs data task
        dataTask.resume()
        return dataTask
    }
    
    /// Convenience function to construct a url and network request,
    /// and perform a network call all at once.
    /// Decodes data into generic decodable types T and E
    /// (T on success and E on failure)
    ///
    /// If no data is expected to be returned, declare success closure's parameter as type `Data`
    ///
    /// - Parameter baseURLString: The starting url for your network call as a string
    /// - Parameter appendingPaths: An array of the paths to append to the end of the base url in order
    /// - Parameter queries: A dictionary of query keys and values to be appended to the end of the final url
    /// - Parameter method: The desired HTTP method for the request
    ///  as an instance of `NetworkManager.Method` enum
    /// - Parameter headers: The headers as a dictionary to attach to the request
    /// - Parameter encodedData: The data to attach to the body of the request
    /// - Parameter decoder: Used to decode data returned from network call .
    /// Defaults to a new instance of `JSONDecoder`.
    ///
    /// - Returns: The data task that was performed as a discardable result
    /// if the url was successfully constructed.
    /// If not no data task is performed or returned.
    @discardableResult
    func makeRequest<T: Decodable, E: Decodable>(baseURLString: String, appendingPaths: [String] = [], queries: [String: String] = [:], method: HTTPMethod = .get, headers: [String: String] = [:], encodedData: Data? = nil, decoder: JSONDecoder = JSONDecoder(), completion: @escaping (NetworkCompletion<T, E>) -> Void) -> URLSessionDataTask? {
        // Constructs url
        guard let url = Self.constructURL(baseURLString: baseURLString, appendingPaths: appendingPaths, queries: queries) else {
            completion(.failure(response: nil, error: .constructingURLFailed))
            return nil
        }
        // Constructs network request
        let request = Self.constructRequest(method: method, url: url, headers: headers, encodedData: encodedData)
        // makes request
        let dataTask = makeRequest(request: request, decoder: decoder,  completion: completion)
        return dataTask
    }
}
