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

class ProtocolErrorTests: KituraTest {
    
    static var allTests: [(String, (ProtocolErrorTests) -> () throws -> Void)] {
        return [
            ("testBinaryAndTextFrames", testBinaryAndTextFrames),
            ("testJustContinuationFrame", testJustContinuationFrame),
            ("testJustFinalContinuationFrame", testJustFinalContinuationFrame),
            ("testTextAndBinaryFrames", testTextAndBinaryFrames)
        ]
    }
    
    func testBinaryAndTextFrames() {
        register(closeReason: .protocolError)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let textPayload = self.payload(text: "testing 1 2 3")
            
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "A text frame must be the first in the message")
            expectedPayload.append(part.bytes, length: part.length)
            
            self.performTest(framesToSend: [(false, self.opcodeBinary, binaryPayload),
                                            (true, self.opcodeText, textPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testJustContinuationFrame() {
        register(closeReason: .protocolError)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let payload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Continuation sent with prior binary or text frame")
            expectedPayload.append(part.bytes, length: part.length)
            
            self.performTest(framesToSend: [(false, self.opcodeContinuation, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testJustFinalContinuationFrame() {
        register(closeReason: .protocolError)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let payload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Continuation sent with prior binary or text frame")
            expectedPayload.append(part.bytes, length: part.length)
            
            self.performTest(framesToSend: [(true, self.opcodeContinuation, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testTextAndBinaryFrames() {
        register(closeReason: .protocolError)
        
        performServerTest() { expectation in
            
            let textPayload = self.payload(text: "testing 1 2 3")
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "A binary frame must be the first in the message")
            expectedPayload.append(part.bytes, length: part.length)
            
            self.performTest(framesToSend: [(false, self.opcodeText, textPayload),
                                            (true, self.opcodeBinary, binaryPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }
}
