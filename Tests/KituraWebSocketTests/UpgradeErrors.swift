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

@testable import KituraWebSocket
@testable import KituraNet
import Socket

class UpgradeErrors: KituraTest {
    
    static var allTests: [(String, (UpgradeErrors) -> () throws -> Void)] {
        return [
            ("testNoSecWebSocketKey", testNoSecWebSocketKey),
            ("testNoSecWebSocketVersion", testNoSecWebSocketVersion),
            ("testNoService", testNoService)
        ]
    }
    
    func testNoSecWebSocketKey() {
        WebSocket.factory.clear()
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(forProtocolVersion: "13", toPath: "/testing123", usingKey: nil) else { return }
     
            self.checkUpgradeResponse(from: socket, expectedMessage: "Sec-WebSocket-Key header missing in the upgrade request", expectation: expectation)
        }
    }
    
    func testNoSecWebSocketVersion() {
        WebSocket.factory.clear()
        
        performServerTest(asyncTasks: { expectation in
            guard let socket = self.sendUpgradeRequest(forProtocolVersion: nil, toPath: "/testing123", usingKey: nil) else { return }
            
            self.checkUpgradeResponse(from: socket, expectedMessage: "Sec-WebSocket-Version header missing in the upgrade request", expectation: expectation)
        },
        { expectation in
            guard let socket = self.sendUpgradeRequest(forProtocolVersion: "12", toPath: "/testing123", usingKey: nil) else { return }
            
            self.checkUpgradeResponse(from: socket, expectedMessage: "Only WebSocket protocol version 13 is supported", expectation: expectation)
        })
    }
    
    func testNoService() {
        WebSocket.factory.clear()
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(forProtocolVersion: "13", toPath: "/testing123", usingKey: "test") else { return }
            
            self.checkUpgradeResponse(from: socket, expectedMessage: "No service has been registered for the path /testing123", expectation: expectation)
        }
    }
    
    private func checkUpgradeResponse(from: Socket, expectedMessage: String, expectation: XCTestExpectation) {
        let (rawResponse, _) = self.processUpgradeResponse(socket: from)
        
        guard let response = rawResponse else {
            XCTFail("Failed to get a response from the upgrade request")
            return
        }
        
        XCTAssertEqual(response.httpStatusCode, HTTPStatusCode.badRequest, "Returned status code on upgrade request was \(response.httpStatusCode) and not \(HTTPStatusCode.badRequest)")
        
        do {
            let body = try response.readString()
            XCTAssertEqual(body, expectedMessage, "The received error message [\(String(describing: body))] was not equal to the expected one [\(expectedMessage)]")
            
            expectation.fulfill()
        }
        catch {
            XCTFail("Failed to read the error message from the failed upgrade")
        }
    }
}
