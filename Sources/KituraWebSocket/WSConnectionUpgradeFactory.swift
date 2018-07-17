/*
 * Copyright IBM Corporation 2016, 2017, 2018
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
import KituraNIO
import NIO
import NIOHTTP1

public class WSConnectionUpgradeFactory: ProtocolHandlerFactory {
    private var registry = Dictionary<String, WebSocketService>()

    public let name = "websocket"

    init() {
        ConnectionUpgrader.register(handlerFactory: self)
    }

    public func handler(for request: ServerRequest) -> ChannelHandler {
        let wsRequest = WSServerRequest(request: request)
        let service = registry[wsRequest.urlURL.path]

        let connection = WebSocketConnection(request: wsRequest)
        connection.service = service

        return connection
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
