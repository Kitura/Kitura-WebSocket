import Foundation
import KituraNet
import KituraWebSocket
import Dispatch

class EchoService: WebSocketService {

    public func connected(connection: WebSocketConnection) {}

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {}

    public func received(message: Data, from: WebSocketConnection) {
        from.send(message: message)
    }

    public func received(message: String, from: WebSocketConnection) {
        from.send(message: message)
    }
}

WebSocket.register(service: EchoService(), onPath: "/")
let port = 9001

do {
    _ = try HTTPServer.listen(on: port, delegate: nil)
} catch {
    print("Unable to start server")
}

dispatchMain()
