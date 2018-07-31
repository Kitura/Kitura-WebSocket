/*
 * Copyright IBM Corporation 2016-2017
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

import Cryptor
import KituraNet

/// The implementation of the ConnectionUpgradeFactory protocol for the WebSocket protocol.
/// Participates in the HTTP protocol upgrade process when upgarding to the WebSocket protocol. 
public class WSConnectionUpgradeFactory: ConnectionUpgradeFactory {
    private var registry = Dictionary<String, WebSocketService>()
    
    private let wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    
    /// The name of the protocol supported by this `ConnectionUpgradeFactory`.
    public let name = "websocket"
    
    init() {
        ConnectionUpgrader.register(factory: self)
    }
    
    /// "Upgrade" a connection to the WebSocket protocol. Invoked by the KituraNet.ConnectionUpgrader when
    /// an upgrade request is being handled.
    ///
    /// - Parameter handler: The `IncomingSocketHandler` that is handling the connection being upgraded.
    /// - Parameter request: The `ServerRequest` object of the incoming "upgrade" request.
    /// - Parameter response: The `ServerResponse` object that will be used to send the response of the "upgrade" request.
    ///
    /// - Returns: A tuple of the created `WSSocketProcessor` and a message to send as the body of the response to
    ///           the upgrade request. The `WSSocketProcessor` will be nil if the upgrade request wasn't successful.
    ///           If the message is nil, the response will not contain a body.
    public func upgrade(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) -> (IncomingSocketProcessor?, String?) {

        guard let protocolVersion = request.headers["Sec-WebSocket-Version"] else {
            return (nil, "Sec-WebSocket-Version header missing in the upgrade request")
        }
        
        guard protocolVersion[0] == "13" else {
            response.headers["Sec-WebSocket-Version"] = ["13"]
            return (nil, "Only WebSocket protocol version 13 is supported")
        }
        
        guard let securityKey = request.headers["Sec-WebSocket-Key"] else {
            return (nil, "Sec-WebSocket-Key header missing in the upgrade request")
        }
        
        guard let service = registry[request.urlURL.path] else {
            return (nil, "No service has been registered for the path \(request.urlURL.path)")
        }
        
        let sha1 = Digest(using: .sha1)
        let sha1Bytes = sha1.update(string: securityKey[0] + wsGUID)!.final()
        let sha1Data = Data(bytes: sha1Bytes, count: sha1Bytes.count)
        response.headers["Sec-WebSocket-Accept"] =
                           [sha1Data.base64EncodedString(options: .lineLength64Characters)]
        response.headers["Sec-WebSocket-Protocol"] = request.headers["Sec-WebSocket-Protocol"]
        
        let connection = WebSocketConnection(request: request, service: service)
        let processor = WSSocketProcessor(connection: connection)
        connection.processor = processor
        
        return (processor, nil)
    }
    
    func register(service: WebSocketService, onPath: String) {
        let path: String
        if onPath.hasPrefix("/") {
            path = onPath
        }
        else {
            path = "/" + onPath
        }
        registry[path] = service
    }
    
    func unregister(path thePath: String) {
        let path: String
        if thePath.hasPrefix("/") {
            path = thePath
        }
        else {
            path = "/" + thePath
        }
        registry.removeValue(forKey: path)
    }
    
    /// Clear the `WebSocketService` registry. Used in testing.
    func clear() {
        registry.removeAll()
    }
}
