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

class ConnectionCleanupTests: KituraTest {

    static var allTests: [(String, (ConnectionCleanupTests) -> () throws -> Void)] {
        return [
            ("testClientChannelClose", testClientChannelClose),
        ]
    }

    func testClientChannelClose() {
        let service = register(closeReason: .closedAbnormally, connectionTimeout: nil)
        
        performServerTest() { expectation in
            XCTAssertEqual(service.connections.count, 0, "Connections left on service at start of test")
            let connected = DispatchSemaphore(value: 0)
            guard let socket = self.sendUpgradeRequest(toPath: self.servicePath, usingKey: self.secWebKey, semaphore: connected) else { return }
            connected.wait()
            usleep(3000)
            XCTAssertEqual(service.connections.count, 1, "Failed to create connection to service")
            let connections = Array(service.connections.values)
            connections[0].ctx.eventLoop.execute {
                connections[0].ctx.close(promise: nil)
            }
            usleep(3000)
            XCTAssertEqual(service.connections.count, 0, "Service was not notified of connection disconnect")
            expectation.fulfill()
        }
    }
}

