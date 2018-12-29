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

        performServerTest { expectation in
            let upgradeFailed = DispatchSemaphore(value: 0)
            let message = "Sec-WebSocket-Key header missing in the upgrade request"
            guard let _ = self.sendUpgradeRequest(forProtocolVersion: "13", toPath: "/testing123", usingKey: nil, semaphore: upgradeFailed,
                errorMessage: message) else { return }
            upgradeFailed.wait()
            expectation.fulfill()
        }
    }

    func testNoSecWebSocketVersion() {
        WebSocket.factory.clear()

        performServerTest(asyncTasks: { expectation in
            let upgradeFailed = DispatchSemaphore(value: 0)
            let message = "Sec-WebSocket-Version header missing in the upgrade request"
            guard let _ = self.sendUpgradeRequest(forProtocolVersion: nil, toPath: "/testing123", usingKey: self.secWebKey, semaphore: upgradeFailed, errorMessage: message) else { return }
            upgradeFailed.wait()
            expectation.fulfill()
        }, { expectation in
            let upgradeFailed = DispatchSemaphore(value: 0)
            let message = "Only WebSocket protocol version 13 is supported"
            guard let _ = self.sendUpgradeRequest(forProtocolVersion: "12", toPath: "/testing123", usingKey: self.secWebKey, semaphore: upgradeFailed, errorMessage: message) else { return }
            upgradeFailed.wait()
            expectation.fulfill()
        })
    }

    func testNoService() {
        WebSocket.factory.clear()

        performServerTest { expectation in
            let upgradeFailed = DispatchSemaphore(value: 0)
            let errorMessage = "No service has been registered for the path /testing123"
            guard let _ = self.sendUpgradeRequest(forProtocolVersion: "13", toPath: "/testing123", usingKey: self.secWebKey, semaphore: upgradeFailed, errorMessage: errorMessage) else { return }
            upgradeFailed.wait()
            expectation.fulfill()
        }
    }
}
