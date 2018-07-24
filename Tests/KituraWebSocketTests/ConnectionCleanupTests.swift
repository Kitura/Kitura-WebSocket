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
@testable import KituraWebSocket
import Socket

class ConnectionCleanupTests: KituraTest {
    
    static var allTests: [(String, (ConnectionCleanupTests) -> () throws -> Void)] {
        return [
            ("testSingleConnectionTimeOut", testSingleConnectionTimeOut),
            ("testNilConnectionTimeOut", testNilConnectionTimeOut),
            ("testPingKeepsConnectionAlive", testPingKeepsConnectionAlive),
            ("testMultiConnectionTimeOut", testMultiConnectionTimeOut),
        ]
    }
    
    func testNilConnectionTimeOut() {
        let service = register(closeReason: .noReasonCodeSent, connectionTimeout: nil)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            sleep(3)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was unexpectantly cleaned up")
            socket.close()
            usleep(150)
            expectation.fulfill()
        }
    }
    
    func testSingleConnectionTimeOut() {
        let service = register(closeReason: .closedAbnormally, connectionTimeout: 1)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            sleep(3)
            XCTAssertEqual(service.connections.count, 0, "Stale connection was not cleaned up")
            expectation.fulfill()
        }
    }
    
    func testPingKeepsConnectionAlive() {
        let service = register(closeReason: .noReasonCodeSent, connectionTimeout: 1)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            sleep(1)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            sleep(1)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            sleep(1)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was unexpectantly cleaned up")
            socket.close()
            usleep(150)
            expectation.fulfill()
        }
    }
    
    func testMultiConnectionTimeOut() {
        let service = register(closeReason: .closedAbnormally, connectionTimeout: 1)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            guard let socket2 = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket2, forKey: self.secWebKey)
            XCTAssertEqual(service.connections.count, 2, "Failed to create second connection to service")
            sleep(1)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            sleep(1)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            sleep(1)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was not cleaned up")
            socket.close()
            usleep(150)
            expectation.fulfill()
        }
    }
}
