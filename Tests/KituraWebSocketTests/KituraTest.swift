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
import NIO
import NIOHTTP1
import NIOWebSocket
import Foundation
import Dispatch
import LoggerAPI

class KituraTest: XCTestCase {

    private static let initOnce: () = {
        PrintLogger.use(colored: true)
    }()

    override func setUp() {
        super.setUp()
        //KituraTest.initOnce
    }

    private static var wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    var secWebKey = "test"

    // Note: These two paths must only differ by the leading slash
    let servicePathNoSlash = "wstester"
    let servicePath = "/wstester"

    var  httpRequestEncoder: HTTPRequestEncoder?

    var httpResponseDecoder: ByteToMessageHandler<HTTPResponseDecoder>?

    var httpHandler: HTTPResponseHandler?

    func performServerTest(line: Int = #line, asyncTasks: (XCTestExpectation) -> Void...) {
        let server = HTTP.createServer()
        server.allowPortReuse = true
        do {
            try server.listen(on: 8080)

            let requestQueue = DispatchQueue(label: "Request queue")

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async {
                    asyncTask(expectation)
                }
            }

            waitForExpectations(timeout: 10) { error in
                // blocks test until request completes
                server.stop()
                XCTAssertNil(error)
            }
        } catch {
            XCTFail("Test failed. Error=\(error)")
        }
    }

    func performTest(framesToSend: [(Bool, Int, NSData)], masked: [Bool] = [],
                     expectedFrames: [(Bool, Int, NSData)], expectation: XCTestExpectation, compressed: Bool = false) {
        precondition(masked.count == 0 || framesToSend.count == masked.count)
        let upgraded = DispatchSemaphore(value: 0)
        guard let channel = sendUpgradeRequest(toPath: servicePath, usingKey: secWebKey, semaphore: upgraded, compressed: compressed) else { return }
        upgraded.wait()
        do {
            _ = try channel.pipeline.removeHandler(httpRequestEncoder!).wait()
            _ = try channel.pipeline.removeHandler(httpResponseDecoder!).wait()
            _ = try channel.pipeline.removeHandler(httpHandler!).wait()
            try channel.pipeline.addHandler(WebSocketClientHandler(expectedFrames: expectedFrames, expectation: expectation, compressed: compressed), position: .first).wait()
        } catch let error {
           Log.error("Error: \(error)")
        }
        for idx in 0..<framesToSend.count {
            let masked = masked.count == 0 ? true : masked[idx]
            let (finalToSend, opCodeToSend, payloadToSend) = framesToSend[idx]
            self.sendFrame(final: finalToSend, withOpcode: opCodeToSend, withMasking: masked, withPayload: payloadToSend, on: channel, lastFrame: idx == framesToSend.count-1, compressed: compressed)
        }
    }

    func register(onPath: String? = nil, closeReason: WebSocketCloseReasonCode, testServerRequest: Bool = false, pingMessage: String? = nil) {
        let service = TestWebSocketService(closeReason: closeReason, testServerRequest: testServerRequest, pingMessage: pingMessage)
        WebSocket.register(service: service, onPath: onPath ?? servicePath)
    }

    func clientChannelInitializer(channel: Channel) -> EventLoopFuture<Void> {
        self.httpRequestEncoder = HTTPRequestEncoder()
        self.httpResponseDecoder =  ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes))
        return channel.pipeline.addHandlers(self.httpRequestEncoder!, self.httpResponseDecoder!, position: .last).flatMap {
            channel.pipeline.addHandler(self.httpHandler!)
        }
    }

    func sendUpgradeRequest(forProtocolVersion: String? = "13", toPath: String, usingKey: String?, semaphore: DispatchSemaphore, errorMessage: String? = nil, compressed: Bool = false) -> Channel? {
        self.httpHandler = HTTPResponseHandler(key: usingKey ?? "", semaphore: semaphore, errorMessage: errorMessage)
        let clientBootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer(clientChannelInitializer)

        do {
            let channel = try clientBootstrap.connect(host: "localhost", port: 8080).wait()
            var request = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: HTTPMethod.method(from: "GET"), uri: toPath)
            var headers = HTTPHeaders()
            headers.add(name: "Host", value: "localhost:8080")
            headers.add(name: "Upgrade", value: "websocket")
            headers.add(name: "Connection", value: "Upgrade")
            if let protocolVersion = forProtocolVersion {
                headers.add(name: "Sec-WebSocket-Version", value: protocolVersion)
            }
            if let key = usingKey {
                headers.add(name: "Sec-WebSocket-Key", value: key)
            }
            if compressed {
                headers.add(name: "Sec-WebSocket-Extensions", value: "permessage-deflate")
            }
            request.headers = headers
            channel.write(NIOAny(HTTPClientRequestPart.head(request)), promise: nil)
            try channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil))).wait()
            return channel
        } catch let error {
            Log.error("Error: \(error)")
            XCTFail("Sending the upgrade request failed")
            return nil
        }
    }

    static func checkUpgradeResponse(_ httpStatusCode: HTTPStatusCode, _ secWebAccept: String, _ forKey: String) {
        XCTAssertEqual(httpStatusCode, HTTPStatusCode.switchingProtocols,
                       "Returned status code on upgrade request was \(httpStatusCode) and not \(HTTPStatusCode.switchingProtocols)")

        let sha1 = Digest(using: .sha1)
        let key: String = forKey + KituraTest.wsGUID
        let sha1Bytes = sha1.update(string: key)!.final()
        let sha1Data = NSData(bytes: sha1Bytes, length: sha1Bytes.count)
        let secWebAcceptExpected = sha1Data.base64EncodedString(options: .lineLength64Characters)

        XCTAssertEqual(secWebAccept, secWebAcceptExpected,
                       "The Sec-WebSocket-Accept header value was [\(secWebAccept)] and not the expected value of [\(secWebAcceptExpected)]")
    }

    static func checkUpgradeFailureResponse(_ httpStatusCode: HTTPStatusCode, _ errorMessage: String) {
        XCTAssertEqual(httpStatusCode, HTTPStatusCode.badRequest,
                       "Returned status code on upgrade request was \(httpStatusCode) and not \(HTTPStatusCode.badRequest)")
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }
}

class HTTPResponseHandler: ChannelInboundHandler {

    public typealias InboundIn = HTTPClientResponsePart

    let errorMessage: String?

    let key: String

    let upgradeDoneOrRefused: DispatchSemaphore

    public init(key: String, semaphore: DispatchSemaphore, errorMessage: String? = nil) {
        self.key = key
        self.upgradeDoneOrRefused = semaphore
        self.errorMessage = errorMessage
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch response {
        case .head(let header):
            let statusCode = HTTPStatusCode(rawValue: Int(header.status.code))!
            let secWebSocketAccept = header.headers["Sec-WebSocket-Accept"]
            if let errorMessage = errorMessage {
                KituraTest.checkUpgradeFailureResponse(statusCode, errorMessage)
            } else {
                KituraTest.checkUpgradeResponse(statusCode, secWebSocketAccept[0], key)
                upgradeDoneOrRefused.signal()
            }
        case .body(let buffer):
            XCTAssertEqual(buffer.getString(at: 0, length: buffer.readableBytes) ?? "", errorMessage!)
            upgradeDoneOrRefused.signal()
        default: break
        }
    }
}

extension Bool {
    mutating func toggle() {
        self = !self
    }
}

// We'd want to able to remove HTTPRequestEncoder and HTTPResponseHandler by hand, following a successful upgrade to WebSocket
extension HTTPRequestEncoder: RemovableChannelHandler { }
extension HTTPResponseHandler: RemovableChannelHandler { }
