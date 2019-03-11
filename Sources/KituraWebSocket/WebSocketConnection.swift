/*
 * Copyright IBM Corporation 2016, 2017, 2018
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
 */

import KituraNet
import NIO
import NIOWebSocket
import Foundation
import NIOHTTP1
import LoggerAPI

public class WebSocketConnection {

    enum MessageState {
        case binary, text, unknown
    }

    private var messageState: MessageState = .unknown

    weak var service: WebSocketService?

    public let id = UUID().uuidString

    public let request: ServerRequest

    var awaitClose = false

    var active = true

    var message: ByteBuffer?

    var context: ChannelHandlerContext?

    private var errors: [String] = []

    init(request: ServerRequest) {
        self.request = request
    }

    public func close(reason: WebSocketCloseReasonCode? = nil, description: String? = nil) {
        closeConnection(reason: reason?.webSocketErrorCode(), description: description, hard: false)
    }

    public func drop(reason: WebSocketCloseReasonCode? = nil, description: String? = nil) {
        closeConnection(reason: reason?.webSocketErrorCode(), description: description, hard: true)
    }

    public func ping(withMessage: String? = nil) {
        guard active else { return }
        guard let context = self.context else {
            Log.error("ChannelHandlerContext unavailable")
            return
        }
        if let message = withMessage {
            var buffer = context.channel.allocator.buffer(capacity: message.count)
            buffer.writeString(message)
            sendMessage(with: .ping, data: buffer)
        } else {
            let emptyBuffer = context.channel.allocator.buffer(capacity: 1)
            sendMessage(with: .ping, data: emptyBuffer)
        }
    }

    public func send(message: Data, asBinary: Bool = true) {
       guard active else { return }
       guard let context = self.context else {
           Log.error("ChannelHandlerContext unavailable")
           return
       }
       var buffer = context.channel.allocator.buffer(capacity: message.count)
       buffer.writeBytes(message)
       sendMessage(with: asBinary ? .binary : .text, data: buffer)
    }

    public func send(message: String) {
        guard active else { return }
        guard let context = self.context else {
            Log.error("ChannelHandlerContext unavailable")
            return
        }
        context.eventLoop.execute {
            var buffer = context.channel.allocator.buffer(capacity: message.count)
            buffer.writeString(message)
            self.sendMessage(with: .text, data: buffer)
        }
    }
}

extension WebSocketConnection: ChannelInboundHandler {
    public typealias InboundIn = WebSocketFrame
    public typealias OutboundOut = WebSocketFrame

    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        guard context.channel.isActive else { return }
        self.fireConnected()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        do {
            try validateRSV(frame: frame)
            guard frame.extensionData == nil else {
                connectionClosed(reason: .protocolError, description: "Extension data must be nil when no extension is negotiated")
                return
            }
        } catch {
            connectionClosed(reason: .protocolError, description: "\(errors.joined(separator: ",")) must be 0 unless an extension is negotiated that defines meanings for non-zero values")
        }

        var data = unmaskedData(frame: frame)
        switch frame.opcode {
        case .text:
            guard messageState == .unknown else {
                connectionClosed(reason: .protocolError, description: "A text frame must be the first in the message")
                return
            }

            guard frame.maskKey != nil else {
                connectionClosed(reason: .protocolError, description: "Received a frame from a client that wasn't masked")
                return
            }

            if frame.fin {
                if let utf8Text = data.getString(at: 0, length: data.readableBytes, encoding: .utf8) {
                    //If text is an empty string, the client might have sent the null character u{00}
                    var text = utf8Text
                    if text == "" {
                        text = data.getString(at: 0, length: data.readableBytes) ?? ""
                    }
                    fireReceivedString(message: text)
                    } else {
                        closeConnection(reason: .dataInconsistentWithMessage, description: "Failed to convert received payload to UTF-8 String", hard: true)
                    }
            } else {
                message =  context.channel.allocator.buffer(capacity: data.readableBytes)
                var buffer = data
                messageState = .text
                message?.writeBuffer(&buffer)
            }

        case .binary:
            guard messageState == .unknown else {
                connectionClosed(reason: .protocolError, description: "A binary frame must be the first in the message")
                return
            }

            guard frame.maskKey != nil else {
                connectionClosed(reason: .protocolError, description: "Received a frame from a client that wasn't masked")
                return
            }

            if frame.fin {
                fireReceivedData(data: data.getData(at: 0, length: data.readableBytes) ?? Data())
            } else {
                message =  context.channel.allocator.buffer(capacity: data.readableBytes)
                message?.writeBuffer(&data)
                messageState = .binary
            }

        case .continuation:
            guard messageState != .unknown else {
                connectionClosed(reason: .protocolError, description: "Continuation sent with prior binary or text frame")
                return
            }

            message?.writeBuffer(&data)
            guard let message = message else { return }

            if frame.fin {
                switch messageState {
                case .binary:
                    fireReceivedData(data: message.getData(at: 0, length: message.readableBytes) ?? Data())
                case .text:
                    if let text = message.getString(at: 0, length: message.readableBytes, encoding: .utf8) {
                        fireReceivedString(message: text)
                    } else {
                        connectionClosed(reason: .dataInconsistentWithMessage, description: "Failed to convert received payload to UTF-8 String")
                    }
                case .unknown: //not possible
                    break
                }
                messageState = .unknown
            }

        case .connectionClose:
            if active {
                let reasonCode: WebSocketErrorCode
                var description: String?
                if frame.length >= 2 && frame.length < 126 {
                    reasonCode = data.readWebSocketErrorCode()?.protocolErrorIfInvalid() ?? WebSocketErrorCode.unknown(0)
                    description = data.getString(at: data.readerIndex, length: data.readableBytes, encoding: .utf8)
                    if description == nil {
                        closeConnection(reason: .dataInconsistentWithMessage, description: "Failed to convert received close message to UTF-8 String", hard: true)
                        return
                    }
                } else if frame.length == 0 {
                    reasonCode = .normalClosure
                } else {
                    connectionClosed(reason: .protocolError, description: "Close frames, that have a payload, must be between 2 and 125 octets inclusive")
                    return
                }
                connectionClosed(reason: reasonCode, description: description)
            }

        case .ping:
            guard frame.length < 126 else {
                connectionClosed(reason: .protocolError, description: "Control frames are only allowed to have payload up to and including 125 octets")
                return
            }

            guard frame.fin else {
                connectionClosed(reason: .protocolError, description: "Control frames must not be fragmented")
                return
            }
            sendMessage(with: .pong, data: data)

        case .pong: break

        case let code where code.isControlOpcode:
            let intCode = Int(webSocketOpcode: code)
            closeConnection(reason: .protocolError, description: "Parsed a frame with an invalid operation code of \(intCode)", hard: true)

        case let code:
            let intCode = Int(webSocketOpcode: code)
            closeConnection(reason: .protocolError, description: "Parsed a frame with an invalid operation code of \(intCode)", hard: true)
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard let error = error as? NIOWebSocketError else { return }
        switch error {
        case .multiByteControlFrameLength:
            connectionClosed(reason: .protocolError, description: "Control frames are only allowed to have payload up to and including 125 octets")
        case .fragmentedControlFrame:
            connectionClosed(reason: .protocolError, description: "Control frames must not be fragmented")
        default: break
        }
    }

    private func unmaskedData(frame: WebSocketFrame) -> ByteBuffer {
       var frameData = frame.data
       if let maskingKey = frame.maskKey {
           frameData.webSocketUnmask(maskingKey)
       }
       return frameData
    }

    private enum RSVError: Error {
        case invalidRSV
    }

    private func validateRSV(frame: WebSocketFrame) throws {

        if frame.rsv1 {
           errors.append("RSV1")
        }

        if frame.rsv2 {
           errors.append("RSV2")
        }

        if frame.rsv3 {
            errors.append("RSV3")
        }

        guard errors.isEmpty else {
            throw RSVError.invalidRSV
        }
    }
}

extension WebSocketConnection {

    func connectionClosed(reason: WebSocketErrorCode, description: String? = nil, reasonToSendBack: WebSocketErrorCode? = nil) {
        guard let context = self.context else {
             Log.error("ChannelHandlerContext unavailable")
             return
        }
        if context.channel.isWritable {
             closeConnection(reason: reasonToSendBack ?? reason, description: description, hard: true)
             fireDisconnected(reason: reason)
        } else {
            context.close(promise: nil)
        }
    }

    func sendMessage(with opcode: WebSocketOpcode, data: ByteBuffer) {
        guard let context = context else {
            Log.error("ChannelHandlerContext unavailable")
            return
        }
        guard context.channel.isWritable else {
            //TODO: Log an error
            return
        }

        guard !self.awaitClose else {
            //TODO: Log an error
            return
        }

        let frame = WebSocketFrame(fin: true, opcode: opcode, data: data)
        _ = context.writeAndFlush(self.wrapOutboundOut(frame))
    }

    func closeConnection(reason: WebSocketErrorCode?, description: String?, hard: Bool) {
         guard let context = context else {
             Log.error("ChannelHandlerContext unavailable")
             return
         }
         var data = context.channel.allocator.buffer(capacity: 2)
         data.write(webSocketErrorCode: reason ?? .normalClosure)
         if let description = description {
             data.writeString(description)
         }

         let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
         context.writeAndFlush(self.wrapOutboundOut(frame)).whenComplete { _ in
             if hard {
                 _ = context.close(mode: .output)
             }
         }
         awaitClose = true
    }
}

//Callbacks to the WebSocketService
extension WebSocketConnection {
    func fireConnected() {
        service?.connected(connection: self)
    }

    func fireDisconnected(reason: WebSocketErrorCode) {
        service?.disconnected(connection: self, reason: WebSocketCloseReasonCode.from(webSocketErrorCode: reason))
    }

    func fireReceivedString(message: String) {
        service?.received(message: message, from: self)
    }

    func fireReceivedData(data: Data) {
        service?.received(message: data, from: self)
    }
}

extension WebSocketCloseReasonCode {
    func webSocketErrorCode() -> WebSocketErrorCode {
        let code = Int(self.code())
        return WebSocketErrorCode(codeNumber: code)
    }

    static func from(webSocketErrorCode: WebSocketErrorCode) -> WebSocketCloseReasonCode {
        switch webSocketErrorCode {
        case .normalClosure: return .normal
        case .goingAway: return .goingAway
        case .protocolError: return .protocolError
        case .unacceptableData: return .invalidDataType
        case .dataInconsistentWithMessage: return .invalidDataContents
        case .policyViolation: return .policyViolation
        case .messageTooLarge: return .messageTooLarge
        case .missingExtension: return .extensionMissing
        case .unexpectedServerError: return .serverError
        case .unknown(let code): return .userDefined(code)
        }
    }
}

extension WebSocketErrorCode {
    func protocolErrorIfInvalid() -> WebSocketErrorCode {
        //https://github.com/IBM-Swift/Kitura-WebSocket/pull/36
        if case .unknown(let code) = self, code < 3000 {
            return .protocolError
        }
        return self
    }
}
