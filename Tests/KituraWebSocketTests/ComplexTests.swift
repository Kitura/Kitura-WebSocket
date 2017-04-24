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

class ComplexTests: KituraTest {
    
    static var allTests: [(String, (ComplexTests) -> () throws -> Void)] {
        return [
            ("testBinaryShortAndMediumFrames", testBinaryShortAndMediumFrames),
            ("testBinaryTwoShortFrames", testBinaryTwoShortFrames),
            ("testPingBetweenBinaryFrames", testPingBetweenBinaryFrames),
            ("testPingBetweenTextFrames", testPingBetweenTextFrames),
            ("testTextShortAndMediumFrames", testTextShortAndMediumFrames),
            ("testTextTwoShortFrames", testTextTwoShortFrames)
        ]
    }
    
        func testBinaryShortAndMediumFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let shortBinaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let mediumBinaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            repeat {
                mediumBinaryPayload.append(mediumBinaryPayload.bytes, length: mediumBinaryPayload.length)
            } while mediumBinaryPayload.length < 1000
            
            let expectedBinaryPayload = NSMutableData()
            expectedBinaryPayload.append(shortBinaryPayload.bytes, length: shortBinaryPayload.length)
            expectedBinaryPayload.append(mediumBinaryPayload.bytes, length: mediumBinaryPayload.length)
            
            self.performTest(framesToSend: [(false, self.opcodeBinary, shortBinaryPayload), (true, self.opcodeContinuation, mediumBinaryPayload)],
                             expectedFrames: [(true, self.opcodeBinary, expectedBinaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testBinaryTwoShortFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let expectedBinaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            expectedBinaryPayload.append(&bytes, length: bytes.count)
            
            self.performTest(framesToSend: [(false, self.opcodeBinary, binaryPayload), (true, self.opcodeContinuation, binaryPayload)],
                             expectedFrames: [(true, self.opcodeBinary, expectedBinaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testPingBetweenBinaryFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            
            let expectedBinaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)
            expectedBinaryPayload.append(&bytes, length: bytes.count)
            
            let pingPayload = self.payload(text: "Testing, testing 1,2,3")
            
            self.performTest(framesToSend: [(false, self.opcodeBinary, binaryPayload),
                                            (true, self.opcodePing, pingPayload),
                                            (true, self.opcodeContinuation, binaryPayload)],
                             expectedFrames: [(true, self.opcodePong, pingPayload), (true, self.opcodeBinary, expectedBinaryPayload)],
                             expectation: expectation)
        }
    }
    
    func testPingBetweenTextFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let text = "Testing, testing 1, 2, 3. "
            
            let textPayload = self.payload(text: text)
            
            let textExpectedPayload = self.payload(text: text + text)
            
            let pingPayload = self.payload(text: "Testing, testing 1,2,3")
            
            self.performTest(framesToSend: [(false, self.opcodeText, textPayload),
                                            (true, self.opcodePing, pingPayload),
                                            (true, self.opcodeContinuation, textPayload)],
                             expectedFrames: [(true, self.opcodePong, pingPayload), (true, self.opcodeText, textExpectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testTextShortAndMediumFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let shortText = "Testing, testing 1, 2, 3. "
            let shortTextPayload = self.payload(text: shortText)
            
            var mediumText = ""
            repeat {
                mediumText += "Testing, testing 1,2,3. "
            } while mediumText.characters.count < 1000
            let mediumTextPayload = self.payload(text: mediumText)
            
            let textExpectedPayload = self.payload(text: shortText + mediumText)
            
            self.performTest(framesToSend: [(false, self.opcodeText, shortTextPayload), (true, self.opcodeContinuation, mediumTextPayload)],
                             expectedFrames: [(true, self.opcodeText, textExpectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testTextTwoShortFrames() {
        register(closeReason: .noReasonCodeSent)
        
        performServerTest() { expectation in
            
            let text = "Testing, testing 1, 2, 3. "
            
            let textPayload = self.payload(text: text)
            
            let textExpectedPayload = self.payload(text: text + text)
            
            self.performTest(framesToSend: [(false, self.opcodeText, textPayload), (true, self.opcodeContinuation, textPayload)],
                             expectedFrames: [(true, self.opcodeText, textExpectedPayload)],
                             expectation: expectation)
        }
    }
}
