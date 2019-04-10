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
            ("testNilConnectionTimeOut", testNilConnectionTimeOut),
            ("testSingleConnectionTimeOut", testSingleConnectionTimeOut),
            ("testPingKeepsConnectionAlive", testPingKeepsConnectionAlive),
            ("testMultiConnectionTimeOut", testMultiConnectionTimeOut),
            ("testProccessorClose", testProccessorClose),
        ]
    }
    
    func testNilConnectionTimeOut() {
        let service = register(closeReason: .noReasonCodeSent, connectionTimeout: nil)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            usleep(2500)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            usleep(1500000)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was unexpectedly cleaned up")
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
            usleep(2500)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            usleep(1500000)
            XCTAssertEqual(service.connections.count, 0, "Stale connection was not cleaned up")
            socket.close()
            usleep(150)
            expectation.fulfill()
        }
    }
    
    func testPingKeepsConnectionAlive() {
        let service = register(closeReason: .noReasonCodeSent, connectionTimeout: 1)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            usleep(2500)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            usleep(500000)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            usleep(500000)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            usleep(500000)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was unexpectedly cleaned up")
            self.sendFrame(final: true, withOpcode: self.opcodeClose, withPayload: NSData(), on: socket)
            usleep(500000)
            XCTAssertEqual(service.connections.count, 0, "Connection was not removed even after getting a close opcode")
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
            usleep(2500)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            guard let socket2 = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket2, forKey: self.secWebKey)
            usleep(2500)
            XCTAssertEqual(service.connections.count, 2, "Failed to create second connection to service")
            usleep(500000)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            usleep(500000)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            usleep(500000)
            self.sendFrame(final: true, withOpcode: self.opcodePing, withPayload: NSData(), on: socket)
            XCTAssertEqual(service.connections.count, 1, "Stale connection was not cleaned up")
            socket.close()
            socket2.close()
            usleep(150)
            expectation.fulfill()
        }
    }
    
    func testProccessorClose() {
        let service = register(closeReason: .closedAbnormally, connectionTimeout: nil)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey) else { return }
            let _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            usleep(2500)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            let connections = Array(service.connections.values)
            connections[0].processor?.close()
            usleep(2500)
            XCTAssertEqual(service.connections.count, 0, "Service was not notified of connection disconnect")
            socket.close()
            usleep(150)
            expectation.fulfill()
        }
    }
}
