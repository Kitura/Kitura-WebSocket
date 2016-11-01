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
    
    private static let bufferSize = 2000
    private let buffer: NSMutableData
    
    private var writeLock = DispatchSemaphore(value: 1)
    
    init() {
        buffer = NSMutableData(capacity: WebSocketClient.bufferSize) ?? NSMutableData()
    }
    
    func received(frame: WSFrame) {
        
        print("WebSocketClient: Received a \(frame.finalFrame ? "final " : "")\(frame.opCode) frame")
        print("WebSocketClient: payload is \(frame.payload.length) bytes long")
        
        var zero: CChar = 0
        frame.payload.append(&zero, length: 1)
        print("WebSocketClient: payload=\(String(cString: frame.payload.bytes.assumingMemoryBound(to: CChar.self), encoding: .utf8))")
        frame.payload.length -= 1
        
        switch frame.opCode {
        case .binary:
            break
            
        case .close:
            break
            
        case .continuation:
            break
            
        case .ping:
            sendMessage(withOpCode: .pong, payload: frame.payload)
            
        case .pong:
            break
            
        case .text:
            break
            
        case .unknown:
            break
        }
    }
    
    private func sendMessage(withOpCode: WSFrame.FrameOpcode, payload: NSData) {
        // Need to add logging
        guard let processor = processor else { return }
        
        lockWriteLock()
        
        buffer.length = 0
        WSFrame.createFrameHeader(finalFrame: true, opCode: withOpCode, payloadLength: payload.length, buffer: buffer)
        
        if WebSocketClient.bufferSize <= buffer.length + payload.length {
            buffer.append(payload.bytes, length: payload.length)
            processor.write(from: buffer)
        }
        else {
            processor.write(from: buffer)
            processor.write(from: payload)
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
