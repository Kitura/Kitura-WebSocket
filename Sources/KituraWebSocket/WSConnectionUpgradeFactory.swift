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
import KituraNet
import NIO
import NIOHTTP1

public class WSConnectionUpgradeFactory: ProtocolHandlerFactory {
    private var registry: [String: WebSocketService] = [:]

    private var extensions: [String: WebSocketProtocolExtension] = [:]
    public let name = "websocket"

    init() {
        ConnectionUpgrader.register(handlerFactory: self)
        //We configure the default `permessage-deflate` extension here.
        self.registerExtension(name: "permessage-deflate", impl: PermessageDeflate())
    }

    /// Return a WebSocketConnection channel handler for the given request
    public func handler(for request: ServerRequest) -> ChannelHandler {
        let wsRequest = WSServerRequest(request: request)
        let service = registry[wsRequest.urlURL.path]

        let connection = WebSocketConnection(request: wsRequest)
        connection.service = service

        return connection
    }

    /// Return all the extension handlers enabled for this connection
    public func extensionHandlers(header: String) -> [ChannelHandler] {
        var handlers: [ChannelHandler] = []
        for _extension in header.split(separator: ",") {
            guard let name = _extension.split(separator: ";").first, let impl = extensions[String(name)] else { continue }
            handlers += impl.handlers(header: String(_extension))
        }
        return handlers
    }

    /// Let all the configured extensions negotiate for themselves, build a response header and send it back
    public func negotiate(header: String) -> String {
        var response = ""
        for _extension in header.split(separator: ",") {
            guard let name = _extension.split(separator: ";").first, let impl = extensions[String(name)] else { continue }
            response += impl.negotiate(header: String(_extension))
        }
        return response
    }

    func register(service: WebSocketService, onPath: String) {
        let path: String
        if onPath.hasPrefix("/") {
            path = onPath
        } else {
            path = "/" + onPath
        }
        registry[path] = service
    }

    func unregister(path thePath: String) {
        let path: String
        if thePath.hasPrefix("/") {
            path = thePath
        } else {
            path = "/" + thePath
        }
        registry.removeValue(forKey: path)
    }

    public func isServiceRegistered(at path: String) -> Bool {
        return registry[path] != nil
    }

    /// Clear the `WebSocketService` registry. Used in testing.
    func clear() {
        registry.removeAll()
    }

    /// Register an extension implementation with a given name
    func registerExtension(name: String, impl: WebSocketProtocolExtension) {
        extensions[name] = impl
    }
}

// A protocol to define WebSocket protocol extensions.
// In future, if we wish to support user-defined WebSocket extensions, we'd make this protocol public.
protocol WebSocketProtocolExtension {
    // Return the extension handlers related to this extension. Most extensions may have an input handler and an output handler.
    func handlers(header: String) -> [ChannelHandler]

    // Negotiate for all enabled extensions. This method will be invoked during the initial handshake.
    func negotiate(header: String) -> String
}
