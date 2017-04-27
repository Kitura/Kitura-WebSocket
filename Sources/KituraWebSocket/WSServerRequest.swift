/*
 * Copyright IBM Corporation 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

import KituraNet

/// An internal class used to retain information from the original request that
/// was used to create the WebSocket connection. The ServerRequest from KituraNet
/// may get freed.
class WSServerRequest: ServerRequest {
    
    /// The set of headers received with the incoming request
    let headers = HeadersContainer()
    
    /// The URL from the request in string form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    @available(*, deprecated, message:
    "This contains just the path and query parameters starting with '/'. use 'urlURL' instead")
    var urlString: String { return String(data: url, encoding: .utf8) ?? "" }
    
    /// The URL from the request in UTF-8 form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    let url: Data
    
    private var urlc: URLComponents?
    
    /// The URL from the request as URLComponents
    /// URLComponents has a memory leak on linux as of swift 3.0.1. Use 'urlURL' instead
    @available(*, deprecated, message:
    "URLComponents has a memory leak on linux as of swift 3.0.1. use 'urlURL' instead")
    public var urlComponents: URLComponents {
        if let urlc = self.urlc {
            return urlc
        }
        let urlc = URLComponents(url: self.urlURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        self.urlc = urlc
        return urlc
    }
    
    /// The URL from the request
    let urlURL: URL
    
    /// The IP address of the client
    let remoteAddress: String
    
    /// Major version of HTTP of the request
    var httpVersionMajor: UInt16? = 1
    
    /// Minor version of HTTP of the request
    var httpVersionMinor: UInt16? = 1
    
    /// The HTTP Method specified in the request
    var method: String = "GET"
    
    init(request: ServerRequest) {
        url = request.url
        urlURL = request.urlURL
        remoteAddress = request.remoteAddress
        
        for (key, values) in request.headers {
            headers.append(key, value: values)
        }
    }
    
    /// Read data from the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: The number of bytes read
    func read(into data: inout Data) throws -> Int {
        return 0
    }
    
    /// Read a string from the body of the request.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: An Optional string
    func readString() throws -> String? {
        return nil
    }
    
    
    /// Read all of the data in the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: The number of bytes read
    func readAllData(into data: inout Data) throws -> Int {
        return 0
    }
}
