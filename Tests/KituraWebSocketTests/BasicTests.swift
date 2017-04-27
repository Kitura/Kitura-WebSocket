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

class BasicTests: KituraTest {
    
    static var allTests: [(String, (BasicTests) -> () throws -> Void)] {
        return [
            ("testBinaryLongMessage", testBinaryLongMessage),
            ("testBinaryMediumMessage", testBinaryMediumMessage),
            ("testBinaryShortMessage", testBinaryShortMessage),
            ("testGracefullClose", testGracefullClose),
            ("testPing", testPing),
            ("testPingFromServer", testPingFromServer),
            ("testPingFromServerWithNoText", testPingFromServerWithNoText),
            ("testPingWithText", testPingWithText),
            ("testServerRequest", testServerRequest),
            ("testSuccessfullUpgrade", testSuccessfullUpgrade),
            ("testTextLongMessage", testTextLongMessage),
            ("testTextMediumMessage", testTextMediumMessage),
            ("testTextShortMessage", testTextShortMessage)
        ]
    }
    
    func testBinaryLongMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            repeat {
                binaryPayload.append(binaryPayload.bytes, length: binaryPayload.length)
            } while binaryPayload.length < 100000
            binaryPayload.append(&bytes, length: bytes.count)
            
            self.performTest(framesToSend: [(true, self.opcodeBinary, binaryPayload)],
                             expectedFrames: [(true, self.opcodeBinary, binaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testBinaryMediumMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            repeat {
                binaryPayload.append(binaryPayload.bytes, length: binaryPayload.length)
            } while binaryPayload.length < 1000
            
            self.performTest(framesToSend: [(true, self.opcodeBinary, binaryPayload)],
                             expectedFrames: [(true, self.opcodeBinary, binaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testBinaryShortMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            self.performTest(framesToSend: [(true, self.opcodeBinary, binaryPayload)],
                             expectedFrames: [(true, self.opcodeBinary, binaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testGracefullClose() {
        register(closeReason: .normal)
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return }
            
            let buffer = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            
            self.sendFrame(final: true, withOpcode: self.opcodeClose,
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
    
    func testPing() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let pingPayload = NSData()
            
            self.performTest(framesToSend: [(true, self.opcodePing, pingPayload)],
                             expectedFrames: [(true, self.opcodePong, pingPayload)],
                             expectation: expectation)
        }
    }
    
    func testPingFromServer() {
        register(closeReason: .noReasonCodeSent, pingMessage: "A test of ping")
        
        performServerTest() { expectation in
            
            let socket = self.pingFromServerHelper(text: "A test of ping")
            
            // Close the socket abruptly. Need to wait to let the close percolate up on the other side
            if let socket = socket {
                socket.close()
                usleep(150)
            
                expectation.fulfill()
            }
        }
    }
    
    func testPingFromServerWithNoText() {
        register(closeReason: .noReasonCodeSent, pingMessage: "")
        
        performServerTest() { expectation in
            
            let socket = self.pingFromServerHelper(text: "")
            
            // Close the socket abruptly. Need to wait to let the close percolate up on the other side
            if let socket = socket {
                socket.close()
                usleep(150)
                
                expectation.fulfill()
            }
        }
    }
    
    private func pingFromServerHelper(text: String) -> Socket? {
        let expectedPayload = payload(text: text)
        
        guard let socket = sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return nil }
        
        let buffer = checkUpgradeResponse(from: socket, forKey: self.secWebKey)
        
        let (final, opCode, returnedPayload, _) = self.parseFrame(using: buffer, position: 0, from: socket)
        
        XCTAssert(final, "Expected message wasn't final")
        XCTAssertEqual(opCode, opcodePing, "Opcode wasn't \(opcodePing). It was \(opCode)")
        XCTAssertEqual(expectedPayload, returnedPayload, "The payload [\(returnedPayload)] doesn't equal the expected [\(expectedPayload)]")
        
        self.sendFrame(final: true, withOpcode: opcodePong, withPayload: returnedPayload, on: socket)
        
        return socket
    }
    
    func testPingWithText() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let pingPayload = self.payload(text: "Testing, testing 1,2,3")
            
            self.performTest(framesToSend: [(true, self.opcodePing, pingPayload)],
                             expectedFrames: [(true, self.opcodePong, pingPayload)],
                             expectation: expectation)
        }
    }
    
    func testServerRequest() {
        register(closeReason: .noReasonCodeSent, testServerRequest: true)
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return }
            
            _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            
            sleep(3)       // Wait a bit for the WebSocketService to test the ServerRequest
            
            // Close the socket abruptly. Need to wait to let the close percolate up on the other side
            socket.close()
            usleep(150)
            
            expectation.fulfill()
        }
    }
    
    func testSuccessfullUpgrade() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            guard let socket = self.sendUpgradeRequest(toPath: "/wstester", usingKey: self.secWebKey) else { return }
            
            _ = self.checkUpgradeResponse(from: socket, forKey: self.secWebKey)
            
            // Close the socket abruptly. Need to wait to let the close percolate up on the other side
            socket.close()
            usleep(150)
            
            expectation.fulfill()
        }
    }
    
    func testTextLongMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var text = "Testing, testing 1, 2, 3."
            repeat {
                text += " " + text
            } while text.characters.count < 100000
            let textPayload = self.payload(text: text)
            
            self.performTest(framesToSend: [(true, self.opcodeText, textPayload)],
                             expectedFrames: [(true, self.opcodeText, textPayload)],
                             expectation: expectation)
        }
    }
    
    func testTextMediumMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var text = ""
            repeat {
                text += "Testing, testing 1,2,3. "
            } while text.characters.count < 1000
            let textPayload = self.payload(text: text)
            
            self.performTest(framesToSend: [(true, self.opcodeText, textPayload)],
                             expectedFrames: [(true, self.opcodeText, textPayload)],
                             expectation: expectation)
        }
    }
    
    func testTextShortMessage() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let textPayload = self.payload(text: "Testing, testing 1,2,3")
            
            self.performTest(framesToSend: [(true, self.opcodeText, textPayload)],
                             expectedFrames: [(true, self.opcodeText, textPayload)],
                             expectation: expectation)
        }
    }
}
