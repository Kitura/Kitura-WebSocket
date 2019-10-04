import Foundation

import KituraWebSocket
import LoggerAPI

class EchoService: WebSocketService {

    public func connected(connection: WebSocketConnection) {}

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {}

    public func received(message: Data, from: WebSocketConnection) {
        from.send(message: message)
    }

    public func received(message: String, from: WebSocketConnection) {
        let msgLength = message.utf8.count
        if msgLength > 100 {
            Log.info("Got message of length \(msgLength)... sending it back")
        } else {
            Log.info("Got message '\(message)'... sending it back")
        }
        from.send(message: message)
    }
}
