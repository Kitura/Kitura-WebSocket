/**
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
 **/

import XCTest
import Foundation

@testable import KituraWebSocket

class TestWebSocketService: WebSocketService {
    var connectionId = ""
    let closeReason: WebSocketCloseReasonCode
    
    public init(closeReason: WebSocketCloseReasonCode) {
        self.closeReason = closeReason
    }
    
    public func connected(connection: WebSocketConnection) {
        connectionId = connection.id
    }
    
    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {
        XCTAssertEqual(connectionId, connection.id, "Client ID from connect wasn't client ID from disconnect")
        XCTAssertEqual(Int(closeReason.code()), Int(reason.code()), "Excpected close reason code of \(closeReason) received \(reason)")
    }
    
    public func received(message: Data, from: WebSocketConnection) {
        print("Received a binary message of length \(message.count)")
        from.send(message: message)
    }
    
    public func received(message: String, from: WebSocketConnection) {
        print("Received a String message of length \(message.characters.count)")
        from.send(message: message)
        
        if message == "close" {
            from.close(reason: .goingAway, description: "Going away...")
        }
        else if message == "drop" {
            from.drop(reason: .policyViolation, description: "Droping...")
        }
        else if message == "ping" {
            from.ping(withMessage: "Hello")
        }
    }
}

extension TestWebSocketService: CustomStringConvertible {
    /// Generate a printable version of this enum.
    public var description: String {
        return "TestWebSocketService(closeReason: \(closeReason))"
    }
}
