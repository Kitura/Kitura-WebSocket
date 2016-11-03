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

import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

struct WSFrameParser {
    
    private enum FrameParsingState {
        case initial, opCodeParsed, lengthParsed
    }
    private var state = FrameParsingState.initial
    
    var frame = WSFrame()
    
    var masked = false
    private var payloadLength = -1
    private var mask: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    private let maskSize = 4
    
    mutating func reset() {
        state = .initial
        payloadLength = -1
        frame.payload.length = 0
    }
    
    mutating func parse(_ buffer: NSData, from: Int) -> (Bool, WebSocketError?, Int) {
        var bytesParsed = 0
        var byteIndex = from
        let bytes = buffer.bytes.assumingMemoryBound(to: UInt8.self)
        
        let length = buffer.length
        
        while byteIndex < length && payloadLength != frame.payload.length {
            switch(state) {
            case .initial:
                let (error, bytesConsumed) = parseOpCode(bytes: bytes, from: byteIndex)
                guard error == nil else { return (false, error, 0) }
                
                bytesParsed += bytesConsumed
                byteIndex += bytesConsumed
                state = .opCodeParsed
            
            case .opCodeParsed:
                let (error, bytesConsumed) = parseMaskAndLength(bytes: bytes, from: byteIndex, length: length)
                guard error == nil else { return (false, error, 0) }
                guard bytesConsumed > 0 else { return (false, error, bytesParsed) }
                
                bytesParsed += bytesConsumed
                byteIndex += bytesConsumed
                state = .lengthParsed
                
            case .lengthParsed:
                let bytesConsumed = parsePayload(bytes: bytes, from: byteIndex, length: length)
                
                bytesParsed += bytesConsumed
                byteIndex += bytesConsumed
            }
        }
        
        return (payloadLength == frame.payload.length, nil, bytesParsed)
    }
    
    private mutating func parseOpCode(bytes: UnsafePointer<UInt8>, from: Int) -> (WebSocketError?, Int) {
        let byte = bytes[from]
        frame.finalFrame = byte & 0x80 != 0
        
        let rawOpCode = byte & 0x0f
        if let opCode = WSFrame.FrameOpcode(rawValue: Int(rawOpCode)) {
            self.frame.opCode = opCode
            return (nil, 1)
        }
        else {
            return (.invalidOpCode(rawOpCode), 0)
        }
    }
    
    private mutating func parseMaskAndLength(bytes: UnsafePointer<UInt8>, from: Int, length: Int) -> (WebSocketError?, Int) {
        let byte = bytes[from]
        masked = byte & 0x80 != 0
        
        guard masked else { return (.unmaskedFrame, 0) }
        
        var bytesConsumed = 0
        
        let lengthByte = byte & 0x7f
        switch lengthByte {
        case 126:
            if length - from >= 3 {
                let networkOrderedUInt16 = UnsafeRawPointer(bytes+from+1).assumingMemoryBound(to: UInt16.self)[0]
                
                #if os(Linux)
                    payloadLength = Int(Glibc.ntohs(networkOrderedUInt16))
                #else
                    payloadLength = Int(CFSwapInt16BigToHost(networkOrderedUInt16))
                #endif
                bytesConsumed += 3
            }
        case 127:
            if length - from >= 9 {
                let networkOrderedUInt32 = UnsafeRawPointer(bytes+from+5).assumingMemoryBound(to: UInt32.self)[0]
                
                #if os(Linux)
                    payloadLength = Int(Glibc.ntohl(networkOrderedUInt32))
                #else
                    payloadLength = Int(CFSwapInt32BigToHost(networkOrderedUInt32))
                #endif
                bytesConsumed += 9
            }
            /* Error if length > Int.max */
        default:
            payloadLength = Int(lengthByte)
            bytesConsumed += 1
        }
        
        if bytesConsumed > 0 {
            if length - from - bytesConsumed >= maskSize {
                UnsafeMutableRawPointer(mutating: mask).copyBytes(from: bytes+from+bytesConsumed, count: maskSize)
                bytesConsumed += maskSize
            }
            else {
                bytesConsumed = 0
            }
        }

        return (nil, bytesConsumed)
    }
    
    private mutating func parsePayload(bytes: UnsafePointer<UInt8>, from: Int, length: Int) -> Int {
        let payloadPiece = bytes + from
        var unmaskedBytes = [UInt8](repeating: 0, count: 125)
        var bytesConsumed: Int = 0
        
        let bytesToUnMask = min(payloadLength - frame.payload.length, length - from)
        var bytesUnmasked = frame.payload.length
        
        // Loop to unmask the bytes we have in this frame piece
        while bytesConsumed < bytesToUnMask {
            
            let bytesToUnMaskInLoop = min(unmaskedBytes.count, bytesToUnMask-bytesConsumed)
            
            for index in 0 ..< bytesToUnMaskInLoop {
                unmaskedBytes[index] = payloadPiece[bytesConsumed] ^ mask[bytesUnmasked % maskSize]
                bytesUnmasked += 1
                bytesConsumed += 1
            }
            frame.payload.append(unmaskedBytes, length: bytesToUnMaskInLoop)
        }
        return bytesConsumed
    }
}
