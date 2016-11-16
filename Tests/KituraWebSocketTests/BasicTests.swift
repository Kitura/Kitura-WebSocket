//
//  BasicTests.swift
//  Kitura-WebSocket
//
//  Created by Samuel Kallner on 26/10/2016.
//
//

import Foundation/**
 * Copyright IBM Corporation 2016
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

@testable import Kitura
@testable import KituraNet
@testable import KituraWebSocket

class BasicTests: XCTestCase {
    
    static var allTests: [(String, (BasicTests) -> () throws -> Void)] {
        return [
            ("testPing", testPing)
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testPing() {
        WebSocket.register(service: TestWebSocketService(), onPath: "/wstester")
        
        performServerTest(TestServerDelegate()) { (expectation: XCTestExpectation) in
        }
    }
    
    class TestWebSocketService: WebSocketService {
        public func connected(client: WebSocketClient) {
            print("Connected")
        }
        
        public func disconnected(client: WebSocketClient) {
            print("Disconnected")
        }
        
        public func received(message: Data, from: WebSocketClient) {
            print("Received a binary message of length \(message.count)")
            from.send(message: message)
        }
        
        public func received(message: String, from: WebSocketClient) {
            print("Received a String message of length \(message.characters.count)")
            from.send(message: message)
        }
    }
    
    class TestServerDelegate : ServerDelegate {
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTFail("Server delegate invoked in an Upgrade scenario")
        }
    }
}
