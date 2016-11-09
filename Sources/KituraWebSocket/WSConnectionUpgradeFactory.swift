/*
 * Copyright IBM Corporation 2015
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

public class WSConnectionUpgradeFactory: ConnectionUpgradeFactory {
    private var registry = Dictionary<String, WebSocketService>()
    
    private let wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    
    /// The name of the protocol supported by this `ConnectionUpgradeFactory`. A case insensitive compare is made with this name.
    public let name = "websocket"
    
    init() {
        ConnectionUpgrader.register(factory: self)
    }
    
    /// "Upgrade" a connection to the protocol supported by this `ConnectionUpgradeFactory`.
    ///
    /// - Parameter handler: The `IncomingSocketHandler` that is handling the connection being upgraded.
    /// - Parameter request: The `ServerRequest` object of the incoming "upgrade" request.
    /// - Parameter response: The `ServerResponse` object that will be used to send the response of the "upgrade" request.
    ///
    /// - Returns: A tuple of the created `IncomingSocketProcessor` and a message to send as the body of the response to
    ///           the upgrade request. The `IncomingSocketProcessor` should be nil if the upgrade request wasn't successful.
    ///           If the message is nil, the response will not contain a body.
    ///
    /// - Note: The `ConnectionUpgradeFactory` instance doesn't need to work with the `ServerResponse` unless it
    ///        needs to add special headers to the response.
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
        
        let parsedURL = URLParser(url: request.url, isConnect: false)
        guard let path = parsedURL.path, let service = registry[path] else {
            return (nil, "No service has been registered for the path \(parsedURL.path ?? "(nopath)")")
        }
        
        let sha1 = Digest(using: .sha1)
        let sha1Bytes = sha1.update(string: securityKey[0] + wsGUID)!.final()
        let sha1Data = NSData(bytes: sha1Bytes, length: sha1Bytes.count)
        response.headers["Sec-WebSocket-Accept"] =
                           [sha1Data.base64EncodedString(options: .lineLength64Characters)]
        response.headers["Sec-WebSocket-Protocol"] = request.headers["Sec-WebSocket-Protocol"]
        
        let client = WebSocketClient()
        let processor = WSSocketProcessor(client: client)
        client.processor = processor
        client.service = service
        
        return (processor, nil)
    }
    
    func register(service: WebSocketService, onPath: String) {
        registry[onPath] = service
    }
}
