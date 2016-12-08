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
    
    func sendFrame(final: Bool, withOpcode: Int, withMasking: Bool=true, withPayload: NSData, on: Socket) -> Bool {
        var result = true
        
        let buffer = NSMutableData()
        
        createFrameHeader(final: final, withOpcode: withOpcode, withMasking: withMasking,
                          payloadLength: withPayload.length, buffer: buffer)
        
        var intMask = arc4random()
        var mask: [UInt8] = [0, 0, 0, 0]
        UnsafeMutableRawPointer(mutating: mask).copyBytes(from: &intMask, count: mask.count)
        
        buffer.append(&mask, length: mask.count)
        
        let payloadBytes = withPayload.bytes.bindMemory(to: UInt8.self, capacity: withPayload.length)
        
        for i in 0 ..< withPayload.length {
            var byte = payloadBytes[i] ^ mask[i % 4]
            buffer.append(&byte, length: 1)
        }
        
        do {
            try on.write(from: buffer)
        }
        catch {
            XCTFail("Failed to send a frame. Error=\(error)")
            result = false
        }
        return result
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
            (UnsafeMutableRawPointer(mutating: bytes)+length+1).copyBytes(from: asBytes, count: 2)
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
            (UnsafeMutableRawPointer(mutating: bytes)+length+5).copyBytes(from: asBytes, count: 4)
            length += 9
        }
        if withMasking {
            bytes[1] |= 0x80
        }
        buffer.append(bytes, length: length)
    }
}
