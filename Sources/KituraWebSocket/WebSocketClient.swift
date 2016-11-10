/*
 * Copyright IBM Corporation 2015
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

public class WebSocketClient {
    weak var processor: WSSocketProcessor?
    
    weak var service: WebSocketService? {
        didSet {
            guard let service = service else { return }
            service.connected(client: self)
        }
    }
    
    private static let bufferSize = 2000
    private let buffer: NSMutableData
    
    private var writeLock = DispatchSemaphore(value: 1)
    
    private let message = NSMutableData()
    
    enum MessageStates {
        case binary, text, unknown
    }
    
    private var messageState: MessageStates = .unknown
    
    init() {
        buffer = NSMutableData(capacity: WebSocketClient.bufferSize) ?? NSMutableData()
    }
    
    public func send(message: Data) {
        let dataToWrite = NSData(data: message)
        sendMessage(withOpCode: .binary, payload: dataToWrite.bytes, payloadLength: dataToWrite.length)
    }
    
    public func send(message: String) {
        let count = message.lengthOfBytes(using: .utf8)
        let bufferLength = count+1 // Allow space for null terminator
        var utf8: [CChar] = Array<CChar>(repeating: 0, count: bufferLength)
        if !message.getCString(&utf8, maxLength: bufferLength, encoding: .utf8) {
            // throw something?
        }
        let rawBytes = UnsafeRawPointer(UnsafePointer(utf8))
        sendMessage(withOpCode: .text, payload: rawBytes, payloadLength: count)
    }
    
    func received(frame: WSFrame) {
        
        switch frame.opCode {
        case .binary:
            guard messageState == .unknown else {
                // Need error handling: send close
                return
            }
            
            if frame.finalFrame {
                let data = Data(bytes: frame.payload.bytes, count: frame.payload.length)
                service?.received(message: data, from: self)
            }
            else {
                messageState = .binary
                message.length = 0
                message.append(frame.payload.bytes, length: frame.payload.length)
            }
            
        case .close:
            break
            
        case .continuation:
            guard messageState != .unknown else {
                // Need error handling: send close
                return
            }
            
            message.append(frame.payload.bytes, length: frame.payload.length)
            
            if frame.finalFrame {
                if messageState == .binary {
                    let data = Data(bytes: message.bytes, count: message.length)
                    service?.received(message: data, from: self)
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
                // Need error handling: send close 
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
            service?.received(message: text, from: self)
        }
        else {
            // Error converting to String
        }
        from.length -= 1
    }
    
    private func sendMessage(withOpCode: WSFrame.FrameOpcode, payload: UnsafeRawPointer, payloadLength: Int) {
        // Need to add logging
        guard let processor = processor else { return }
        
        lockWriteLock()
        
        buffer.length = 0
        WSFrame.createFrameHeader(finalFrame: true, opCode: withOpCode, payloadLength: payloadLength, buffer: buffer)
        
        if WebSocketClient.bufferSize >= buffer.length + payloadLength {
            buffer.append(payload, length: payloadLength)
            processor.write(from: buffer)
        }
        else {
            processor.write(from: buffer)
            processor.write(from: payload, length: payloadLength)
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
