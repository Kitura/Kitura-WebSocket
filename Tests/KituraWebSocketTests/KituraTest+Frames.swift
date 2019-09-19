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


@testable import KituraWebSocket
import LoggerAPI
import Socket

import Foundation
#if os(Linux)
    import Glibc
#endif

extension KituraTest {
    
    var opcodeBinary: Int { return 2 }
    var opcodeClose: Int { return 8 }
    var opcodeContinuation: Int { return 0 }
    var opcodePing: Int { return 9 }
    var opcodePong: Int { return 10 }
    var opcodeText: Int { return 1 }
    
    func payload(closeReasonCode: WebSocketCloseReasonCode) -> NSData {
        var tempReasonCodeToSend = UInt16(closeReasonCode.code())
        var reasonCodeToSend: UInt16
        #if os(Linux)
            reasonCodeToSend = Glibc.htons(tempReasonCodeToSend)
        #else
            reasonCodeToSend = CFSwapInt16HostToBig(tempReasonCodeToSend)
        #endif
        
        let payload = NSMutableData()
        let asBytes = UnsafeMutablePointer(&reasonCodeToSend)
        payload.append(asBytes, length: 2)
        
        return payload
    }
    
    func payload(text: String) -> NSData {
        let result = NSMutableData()
        
        let utf8Length = text.lengthOfBytes(using: .utf8)
        var utf8: [CChar] = Array<CChar>(repeating: 0, count: utf8Length + 10) // A little bit of padding
        guard text.getCString(&utf8, maxLength: utf8Length + 10, encoding: .utf8)  else {
            return result
        }
        
        result.append(&utf8, length: utf8Length)
        
        return result
    }
    
    func parseFrame(using: NSMutableData, position: Int, from: Socket) -> (Bool, Int, NSData, Int) {
        var final = false
        var opcode = -1
        let payload = NSMutableData()
        var payloadLength = -1
        var updatedPosition = position
        
        var parsingFrame = true
        
        while parsingFrame {
            updatedPosition = position
            payload.length = 0
            
            (final, opcode, updatedPosition) = parseFrameOpcode(using: using, position: updatedPosition)
            if opcode != -1 {
                
                (payloadLength, updatedPosition) = parseFrameLength(using: using, position: updatedPosition)
                if payloadLength != -1 {
                
                    if using.length >= updatedPosition+payloadLength {
                        payload.append(using.bytes+updatedPosition, length: payloadLength)
                        parsingFrame = false
                        updatedPosition += payloadLength
                    }
                }
            }
            
            if parsingFrame {
                do {
                    let bytesRead = try from.read(into: using)
                    if bytesRead == 0 {
                        parsingFrame = false
                        opcode = -1
                    }
                }
                catch {
                    XCTFail("Reading of WebSocket message from WebService failed. Error=\(error)")
                }
            }
        
        }
        
        return (final, opcode, payload, updatedPosition)
    }
    
    private func parseFrameOpcode(using: NSMutableData, position: Int) -> (Bool, Int, Int) {
        guard using.length > position else { return (false, -1, position) }
        
        let byte = using.bytes.load(fromByteOffset: position, as: UInt8.self)
        return ((byte & 0x80) != 0, Int(byte & 0x7f), position+1)
    }
    
    private func parseFrameLength(using: NSMutableData, position: Int) -> (Int, Int) {
        guard position < using.length else {
            return (-1, position)
        }
        
        let byte = using.bytes.load(fromByteOffset: position, as: UInt8.self)
        if byte & 0x80 != 0 {
            XCTFail("The server isn't suppose to send masked frames")
        }
        var length = Int(byte)
        var bytesConsumed = 1
        if length == 126 {
            guard position+2 < using.length else { return (-1, position+1) }
            
            // We cannot perform an unaligned load of a 16-bit value from the buffer.
            // Instead, create correctly aligned storage for a 16-bit value and copy
            // the bytes from the buffer into its storage.
            let bytes = UnsafeRawBufferPointer(start: using.bytes, count: using.length)
            var networkOrderedUInt16 = UInt16(0)
            withUnsafeMutableBytes(of: &networkOrderedUInt16) { ptr in
                let unalignedUInt16 = UnsafeRawBufferPointer(rebasing: bytes[position+1 ..< position+3])
                #if swift(>=4.1)
                    ptr.copyMemory(from: unalignedUInt16)
                #else
                    ptr.copyBytes(from: unalignedUInt16)
                #endif
            }
            
            #if os(Linux)
                length = Int(Glibc.ntohs(networkOrderedUInt16))
            #else
                length = Int(CFSwapInt16BigToHost(networkOrderedUInt16))
            #endif
            bytesConsumed += 2
        }
        else if length == 127 {
            guard position+8 < using.length else { return (-1, position+1) }

            // We cannot perform an unaligned load of a 32-bit value from the buffer.
            // Instead, create correctly aligned storage for a 32-bit value and copy
            // the bytes from the buffer into its storage.
            let bytes = UnsafeRawBufferPointer(start: using.bytes, count: using.length)
            var networkOrderedUInt32 = UInt32(0)
            withUnsafeMutableBytes(of: &networkOrderedUInt32) { ptr in
                let unalignedUInt32 = UnsafeRawBufferPointer(rebasing: bytes[position+5 ..< position+9])
                #if swift(>=4.1)
                    ptr.copyMemory(from: unalignedUInt32)
                #else
                    ptr.copyBytes(from: unalignedUInt32)
                #endif
            }
            
            #if os(Linux)
                length = Int(Glibc.ntohl(networkOrderedUInt32))
            #else
                length = Int(CFSwapInt32BigToHost(networkOrderedUInt32))
            #endif
            bytesConsumed += 8
        }
        
        return (length, position+bytesConsumed)
    }
    
    func sendFrame(final: Bool, withOpcode: Int, withMasking: Bool=true, withPayload: NSData, on: Socket) {
        let buffer = NSMutableData()
        
        createFrameHeader(final: final, withOpcode: withOpcode, withMasking: withMasking,
                          payloadLength: withPayload.length, buffer: buffer)
        
        var intMask: UInt32
            
        #if os(Linux)
            intMask = UInt32(random())
        #else
            intMask = arc4random()
        #endif
        var mask: [UInt8] = [0, 0, 0, 0]
        #if swift(>=4.1)
        UnsafeMutableRawPointer(mutating: mask).copyMemory(from: &intMask, byteCount: mask.count)
        #else
        UnsafeMutableRawPointer(mutating: mask).copyBytes(from: &intMask, count: mask.count)
        #endif
        buffer.append(&mask, length: mask.count)
        
        let payloadBytes = UnsafeRawBufferPointer(start: withPayload.bytes, count: withPayload.length)
        
        for i in 0 ..< withPayload.length {
            var byte = payloadBytes[i] ^ mask[i % 4]
            buffer.append(&byte, length: 1)
        }
        
        do {
            try on.write(from: buffer)
        }
        catch {
            XCTFail("Failed to send a frame. Error=\(error)")
        }
    }
    
    private func createFrameHeader(final: Bool, withOpcode: Int, withMasking: Bool, payloadLength: Int, buffer: NSMutableData) {
        
        var bytes: [UInt8] = [(final ? 0x80 : 0x00) | UInt8(withOpcode), 0, 0,0,0,0,0,0,0,0]
        var length = 1
        
        if payloadLength < 126 {
            bytes[1] = UInt8(payloadLength)
            length += 1
        } else if payloadLength <= Int(UInt16.max) {
            bytes[1] = 126
            let tempPayloadLengh = UInt16(payloadLength)
            var payloadLengthUInt16: UInt16
            #if os(Linux)
                payloadLengthUInt16 = Glibc.htons(tempPayloadLengh)
            #else
                payloadLengthUInt16 = CFSwapInt16HostToBig(tempPayloadLengh)
            #endif
            let asBytes = UnsafeMutablePointer(&payloadLengthUInt16)
            #if swift(>=4.1)
            (UnsafeMutableRawPointer(mutating: bytes)+length+1).copyMemory(from: asBytes, byteCount: 2)
            #else
            (UnsafeMutableRawPointer(mutating: bytes)+length+1).copyBytes(from: asBytes, count: 2)
            #endif
            length += 3
        } else {
            bytes[1] = 127
            let tempPayloadLengh = UInt32(payloadLength)
            var payloadLengthUInt32: UInt32
            #if os(Linux)
                payloadLengthUInt32 = Glibc.htonl(tempPayloadLengh)
            #else
                payloadLengthUInt32 = CFSwapInt32HostToBig(tempPayloadLengh)
            #endif
            let asBytes = UnsafeMutablePointer(&payloadLengthUInt32)
            #if swift(>=4.1)
            (UnsafeMutableRawPointer(mutating: bytes)+length+5).copyMemory(from: asBytes, byteCount: 4)
            #else
            (UnsafeMutableRawPointer(mutating: bytes)+length+5).copyBytes(from: asBytes, count: 4)
            #endif
            length += 9
        }
        if withMasking {
            bytes[1] |= 0x80
        }
        buffer.append(bytes, length: length)
    }
}
