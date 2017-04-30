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

import LoggerAPI
@testable import KituraWebSocket
@testable import KituraNet
import Cryptor
import Socket

import Foundation
import Dispatch

class KituraTest: XCTestCase {
    
    private static let initOnce: () = {
        PrintLogger.use(colored: true)
    }()
    
    override func setUp() {
        super.setUp()
        KituraTest.initOnce
    }
    
    private var wsGUID: String { return "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" }
    
    var secWebKey: String { return "test" }
    
    func performServerTest(line: Int = #line,
                           asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        let server = HTTP.createServer()
        
        do {
            try server.listen(on: 8080)
        
            let requestQueue = DispatchQueue(label: "Request queue")
        
            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async() {
                    asyncTask(expectation)
                }
            }
        
            waitForExpectations(timeout: 10) { error in
                // blocks test until request completes
                server.stop()
                XCTAssertNil(error)
            }
        }
        catch {
            XCTFail("Test failed. Error=\(error)")
        }
    }
    
    func performTest(framesToSend: [(Bool, Int, NSData)],
                     expectedFrames: [(Bool, Int, NSData)], expectation: XCTestExpectation) {
        guard let socket = sendUpgradeRequest(toPath: "/wstester", usingKey: secWebKey) else { return }
        
        let buffer = checkUpgradeResponse(from: socket, forKey: secWebKey)
        
        for frameToSend in framesToSend {
            let (finalToSend, opCodeToSend, payloadToSend) = frameToSend
            sendFrame(final: finalToSend, withOpcode: opCodeToSend, withPayload: payloadToSend, on: socket)
        }
        
        var position = 0
        for expectedFrame in expectedFrames {
            let (final, opCode, payload, updatedPosition) = parseFrame(using: buffer, position: position, from: socket)
            position = updatedPosition
        
            let (expectedFinal, expectedOpCode, expectedPayload) = expectedFrame
            XCTAssertEqual(final, expectedFinal, "Expected message was\(expectedFinal ? "n't" : "") final")
            XCTAssertEqual(opCode, expectedOpCode, "Opcode wasn't \(expectedOpCode). It was \(opCode)")
            XCTAssertEqual(expectedPayload, payload, "The payload [\(payload)] doesn't equal the expected [\(expectedPayload)]")
        }
        
        // Close the socket abruptly. Need to wait to let the close percolate up on the other side
        socket.close()
        usleep(150)
        
        expectation.fulfill()
    }
    
    func register(closeReason: WebSocketCloseReasonCode, testServerRequest: Bool=false, pingMessage: String?=nil) {
        let service = TestWebSocketService(closeReason: closeReason, testServerRequest: testServerRequest, pingMessage: pingMessage)
        WebSocket.register(service: service, onPath: "/wstester")
    }
    
    func sendUpgradeRequest(forProtocolVersion: String?="13", toPath: String, usingKey: String?) -> Socket? {
        var socket: Socket?
        do {
            socket = try Socket.create()
            try socket?.connect(to: "localhost", port: 8080)
            
            var request = "GET " + toPath + " HTTP/1.1\r\n" +
                "Host: localhost:8080\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n"
            
            if let protocolVersion = forProtocolVersion {
                request += "Sec-WebSocket-Version: " + protocolVersion + "\r\n"
            }
            if let key = usingKey {
                request += "Sec-WebSocket-Key: " + key + "\r\n"
            }
            
            request += "\r\n"
            
            guard let data = request.data(using: .utf8) else { return nil }
            
            try socket?.write(from: data)
        }
        catch let error {
            socket = nil
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
        return socket
    }
    
    func processUpgradeResponse(socket: Socket) -> (ClientResponse?, NSMutableData?) {
        let response = ClientResponse()
        var unparsedData: NSMutableData?
        var errorFlag = false
        
        var keepProcessing = true
        let buffer = NSMutableData()
        
        do {
            while keepProcessing {
                buffer.length = 0
                let count = try socket.read(into: buffer)
                
                if count != 0 {
                    let parserStatus = response.parse(buffer, from: 0)
                    
                    if parserStatus.state == .messageComplete {
                        keepProcessing = false
                        if parserStatus.bytesLeft != 0 {
                            unparsedData = NSMutableData(bytes: buffer.bytes+buffer.length-parserStatus.bytesLeft, length: parserStatus.bytesLeft)
                        }
                    }
                }
                else {
                    keepProcessing = false
                    errorFlag = true
                    XCTFail("Server closed socket prematurely")
                }
            }
        }
        catch let error {
            errorFlag = true
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
        return (errorFlag ? nil : response, unparsedData)
    }
    
    func checkUpgradeResponse(from: Socket, forKey: String) -> NSMutableData {
        let (rawResponse, extraData) = self.processUpgradeResponse(socket: from)
        let buffer = extraData ?? NSMutableData()
        
        guard let response = rawResponse else {
            XCTFail("Failed to get a response from the upgrade request")
            return buffer
        }
        
        XCTAssertEqual(response.httpStatusCode, HTTPStatusCode.switchingProtocols, "Returned status code on upgrade request was \(response.httpStatusCode) and not \(HTTPStatusCode.switchingProtocols)")
        
        if response.httpStatusCode != HTTPStatusCode.switchingProtocols {
            do {
                let body = try response.readString()
                Log.error(body ?? "No error message in body")
            }
            catch {
                Log.error("Failed to read the error message from the failed upgrade")
            }
        }
        
        guard let secWebAccept = response.headers["Sec-WebSocket-Accept"] else {
            XCTFail("Sec-WebSocket-Accept is missing in the upgrade response")
            return buffer
        }
        
        let sha1 = Digest(using: .sha1)
        let sha1Bytes = sha1.update(string: forKey + wsGUID)!.final()
        let sha1Data = NSData(bytes: sha1Bytes, length: sha1Bytes.count)
        let secWebAcceptExpected = sha1Data.base64EncodedString(options: .lineLength64Characters)
        
        XCTAssertEqual(secWebAccept[0], secWebAcceptExpected,
                       "The Sec-WebSocket-Accept header value was [\(secWebAccept[0])] and not the expected value of [\(secWebAcceptExpected)]")
        
        return buffer
    }
    
    func checkCloseReasonCode(payload: NSData, expectedReasonCode: WebSocketCloseReasonCode) {
        XCTAssertEqual(payload.length, MemoryLayout<UInt16>.stride, "The payload wasn't \(MemoryLayout<UInt16>.stride) bytes long. It was \(payload.length) bytes long")
        
        let reasonCode: UInt16
        let networkOrderedUInt16 = UnsafeRawPointer(payload.bytes).assumingMemoryBound(to: UInt16.self)[0]
        
        #if os(Linux)
            reasonCode = Glibc.ntohs(networkOrderedUInt16)
        #else
            reasonCode = CFSwapInt16BigToHost(networkOrderedUInt16)
        #endif
        
        XCTAssertEqual(reasonCode, UInt16(expectedReasonCode.code()), "The close reason code wasn't \(expectedReasonCode) - [\(expectedReasonCode.code())] it was \(reasonCode)")
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }
}

