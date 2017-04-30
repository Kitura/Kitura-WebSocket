/*
 * Copyright IBM Corporation 2016-2017
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

import Dispatch
import Foundation

import KituraNet

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/// Represents a specific WebSocket connection. Provides a unique identifier for
/// the connection and APIs to send messages and control commands to the client
/// at the other end of the connection.
public class WebSocketConnection {
    weak var processor: WSSocketProcessor?
    
    weak var service: WebSocketService?
    
    private static let bufferSize = 2000
    private let buffer: NSMutableData
    
    private var writeLock = DispatchSemaphore(value: 1)

    // Each message from a given socket needs to be processed in order. All callbacks such as
    // connected(...), received(...), or disconnected(...) will be called on this serial queue.
    // Each socket still has its own serial queue which means separate sockets can still be
    // processed concurrently.
    private var callbackQueue = DispatchQueue(label: "SocketCallbackQueue")

    private let message = NSMutableData()
    
    private var active = true
    
    enum MessageStates {
        case binary, text, unknown
    }
    
    /// Unique identifier for this `WebSocketConnection`
    public let id: String
    
    /// The ServerRequest from the original protocol upgrade
    public let request: ServerRequest
    
    private var messageState: MessageStates = .unknown
    
    init(request: ServerRequest) {
        id = UUID().uuidString
        self.request = WSServerRequest(request: request)
        buffer = NSMutableData(capacity: WebSocketConnection.bufferSize) ?? NSMutableData()
    }
    
    /// Close a WebSocket connection by sending a close control command to the client optionally
    /// with the specified reason code and description text.
    ///
    /// - Parameter reason: An optional reason code to send in the close control command
    ///                    describing why the connection was closed. If nil, a reason code
    ///                    of `WebSocketCloseReasonCode.normal` will be sent.
    /// - Parameter description: An optional text description to be sent in the close control frame.
    public func close(reason: WebSocketCloseReasonCode?=nil, description: String?=nil) {
        closeConnection(reason: reason, description: description, hard: false)
    }
    
    /// Forcefully close a WebSocket connection by sending a close control command to the client optionally
    /// with the specified reason code and description text followed by closing the socket.
    ///
    /// - Parameter reason: An optional reason code to send in the close control command
    ///                    describing why the connection was closed. If nil, a reason code
    ///                    of `WebSocketCloseReasonCode.normal` will be sent.
    /// - Parameter description: An optional text description to be sent in the close control frame.
    public func drop(reason: WebSocketCloseReasonCode?=nil, description: String?=nil) {
        closeConnection(reason: reason, description: description, hard: true)
    }
    
    /// Send a ping control frame to the client
    ///
    /// - Parameter withMessage: An optional string to be included in the ping control frame.
    public func ping(withMessage: String?=nil) {
        guard active else { return }
        
        if let message = withMessage {
            let count = message.lengthOfBytes(using: .utf8)
            let bufferLength = count+1 // Allow space for null terminator
            var utf8: [CChar] = Array<CChar>(repeating: 0, count: bufferLength)
            if !message.getCString(&utf8, maxLength: bufferLength, encoding: .utf8) {
                // throw something?
            }
            let rawBytes = UnsafeRawPointer(UnsafePointer(utf8))
            sendMessage(withOpCode: .ping, payload: rawBytes, payloadLength: count)
        }
        else {
            sendMessage(withOpCode: .ping, payload: nil, payloadLength: 0)
        }
    }
    
    /// Send a message to the client contained in a Data struct.
    ///
    /// - Parameter message: A Data struct containing the bytes to be sent to the client as a
    ///                     message.
    /// - Parameter type: asBinary if true, which is the default, the message is sent as a 
    ///                  binary mesage. If false, the message will be sent as a text message
    public func send(message: Data, asBinary: Bool = true) {
        guard active else { return }
        
        let dataToWrite = NSData(data: message)
        sendMessage(withOpCode: asBinary ? .binary : .text, payload: dataToWrite.bytes, payloadLength: dataToWrite.length)
    }
    
    /// Send a text message to the client
    ///
    /// - Parameter message: A String containing the text to be sent to the client as a
    ///                     text message.
    public func send(message: String) {
        guard active else { return }
        
        let count = message.lengthOfBytes(using: .utf8)
        let bufferLength = count+1 // Allow space for null terminator
        var utf8: [CChar] = Array<CChar>(repeating: 0, count: bufferLength)
        if !message.getCString(&utf8, maxLength: bufferLength, encoding: .utf8) {
            // throw something?
        }
        let rawBytes = UnsafeRawPointer(UnsafePointer(utf8))
        sendMessage(withOpCode: .text, payload: rawBytes, payloadLength: count)
    }
    
    func closeConnection(reason: WebSocketCloseReasonCode?, description: String?, hard: Bool) {
        var tempReasonCodeToSend = UInt16((reason ?? .normal).code())
        var reasonCodeToSend: UInt16
        #if os(Linux)
            reasonCodeToSend = Glibc.htons(tempReasonCodeToSend)
        #else
            reasonCodeToSend = CFSwapInt16HostToBig(tempReasonCodeToSend)
        #endif
        
        let payload = NSMutableData()
        let asBytes = UnsafeMutablePointer(&reasonCodeToSend)
        payload.append(asBytes, length: 2)
        
        if let descriptionToSend = description {
            let count = descriptionToSend.lengthOfBytes(using: .utf8)
            let bufferLength = count+1 // Allow space for null terminator
            var utf8: [CChar] = Array<CChar>(repeating: 0, count: bufferLength)
            if !descriptionToSend.getCString(&utf8, maxLength: bufferLength, encoding: .utf8) {
                // throw something?
            }
            payload.append(UnsafePointer(utf8), length: count)
        }
        
        sendMessage(withOpCode: .close, payload: payload.bytes, payloadLength: payload.length)
        active = false
        
        if hard {
            processor?.close()
        }
    }
    
    func connectionClosed(reason: WebSocketCloseReasonCode, description: String?=nil, reasonToSendBack: WebSocketCloseReasonCode? = nil) {
        if active {
            let reasonTosend = reasonToSendBack ?? reason
            closeConnection(reason: reasonTosend, description: description, hard: true)
            
            callbackQueue.async { [weak self] in
                if let strongSelf = self {
                    strongSelf.service?.disconnected(connection: strongSelf, reason: reason)
                }
            }
        }
        else {
            processor?.close()
        }
    }
    
    func fireConnected() {
        guard let service = service else { return }
        
        callbackQueue.async { [weak self] in
            if let strongSelf = self {
                service.connected(connection: strongSelf)
            }
        }
    }
    
    func received(frame: WSFrame) {
        
        switch frame.opCode {
        case .binary:
            guard messageState == .unknown else {
                connectionClosed(reason: .protocolError, description: "A binary frame must be the first in the message")
                return
            }
            
            if frame.finalFrame {
                let data = Data(bytes: frame.payload.bytes, count: frame.payload.length)
                callbackQueue.async { [unowned self] in
                    self.service?.received(message: data, from: self)
                }
            }
            else {
                messageState = .binary
                message.length = 0
                message.append(frame.payload.bytes, length: frame.payload.length)
            }
            
        case .close:
            if active {
                let reasonCode: WebSocketCloseReasonCode
                if frame.payload.length >= 2 {
                    let networkOrderedReasonCode = UnsafeRawPointer(frame.payload.bytes).assumingMemoryBound(to: UInt16.self)[0]
                
                    let reasonCodeInt16: Int16
                    #if os(Linux)
                        reasonCodeInt16 = Int16(Glibc.ntohs(networkOrderedReasonCode))
                    #else
                        reasonCodeInt16 = Int16(CFSwapInt16BigToHost(networkOrderedReasonCode))
                    #endif
                    
                    reasonCode = WebSocketCloseReasonCode.from(code: reasonCodeInt16)                }
                else {
                    reasonCode = .noReasonCodeSent
                }
                
                connectionClosed(reason: reasonCode, reasonToSendBack: .normal)
            }
            break
            
        case .continuation:
            guard messageState != .unknown else {
                connectionClosed(reason: .protocolError, description: "Continuation sent with prior binary or text frame")
                return
            }
            
            message.append(frame.payload.bytes, length: frame.payload.length)
            
            if frame.finalFrame {
                if messageState == .binary {
                    let data = Data(bytes: message.bytes, count: message.length)
                    callbackQueue.async { [unowned self] in
                        self.service?.received(message: data, from: self)
                    }
                } else {
                    fireReceivedString(from: message)
                }
                messageState = .unknown
            }
            
        case .ping:
            sendMessage(withOpCode: .pong, payload: frame.payload.bytes, payloadLength: frame.payload.length)
            
        case .pong:
            break
            
        case .text:
            guard messageState == .unknown else {
                connectionClosed(reason: .protocolError, description: "A text frame must be the first in the message")
                return
            }
            
            if frame.finalFrame {
                fireReceivedString(from: frame.payload)
            }
            else {
                messageState = .text
                message.length = 0
                message.append(frame.payload.bytes, length: frame.payload.length)
            }
            
        case .unknown:
            break
        }
    }
    
    private func fireReceivedString(from: NSMutableData) {
        var zero: CChar = 0
        from.append(&zero, length: 1)
        let bytes = from.bytes.bindMemory(to: CChar.self, capacity: 1)
        if let text = String(cString: bytes, encoding: .utf8) {
            callbackQueue.async { [unowned self] in
                self.service?.received(message: text, from: self)
            }
        }
        else {
            // Error converting to String
        }
        from.length -= 1
    }
    
    private func sendMessage(withOpCode: WSFrame.FrameOpcode, payload: UnsafeRawPointer?, payloadLength: Int) {
        // Need to add logging
        guard let processor = processor else { return }
        
        lockWriteLock()
        
        buffer.length = 0
        WSFrame.createFrameHeader(finalFrame: true, opCode: withOpCode, payloadLength: payloadLength, buffer: buffer)
        
        if let realPayload = payload {
            if WebSocketConnection.bufferSize >= buffer.length + payloadLength {
                buffer.append(realPayload, length: payloadLength)
                processor.write(from: buffer)
            }
            else {
                processor.write(from: buffer)
                processor.write(from: realPayload, length: payloadLength)
            }
        }
        else {
            processor.write(from: buffer)
        }
        
        unlockWriteLock()
    }
    
    private func lockWriteLock() {
        _ = writeLock.wait(timeout: DispatchTime.distantFuture)
    }
    
    private func unlockWriteLock() {
        writeLock.signal()
    }
}
