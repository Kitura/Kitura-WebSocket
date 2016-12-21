/**
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

import LoggerAPI
@testable import KituraNet
@testable import KituraWebSocket
import Cryptor
import Socket

class BasicTests: XCTestCase {
    
    static var allTests: [(String, (BasicTests) -> () throws -> Void)] {
        return [
            ("testGracefullClose", testGracefullClose),
            ("testSuccessfullUpgrade", testSuccessfullUpgrade)
        ]
    }
    
    private let secWebKey = "test"
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testGracefullClose() {
        WebSocket.register(service: TestWebSocketService(closeReason: .normal), onPath: "/wstester")
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return }
            
            let buffer = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey, expectation: expectation)
            
            _ = self.sendFrame(final: true, withOpcode: self.opcodeClose,
                               withPayload: self.payload(closeReasonCode: .normal), on: socket)
            
            let (final, opcode, payload, _) = self.parseFrame(using: buffer, position: 0, from: socket)
            
            XCTAssert(final, "Close message wasn't final")
            XCTAssertEqual(opcode, self.opcodeClose, "Opcode wasn't close. was \(opcode)")
            self.checkCloseReasonCode(payload: payload, expectedReasonCode: .normal)
            
            // Wait a bit for the WebSocketService
            usleep(150)
            
            expectation.fulfill()
        }
    }
    
    func testSuccessfullUpgrade() {
        WebSocket.register(service: TestWebSocketService(closeReason: .noReasonCodeSent), onPath: "/wstester")
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return }
            
            _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey, expectation: expectation)
            
            // Close the socket abruptly. Need to wait to let the close percolate up on th eoter side
            socket.close()
            usleep(150)
            
            expectation.fulfill()
        }
    }
}
