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

struct WSFrame {
    var finalFrame = false
    
    enum FrameOpcode: Int {
        case continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10, unknown = -1
    }
    var opCode = FrameOpcode.unknown
    
    let payload = NSMutableData()
    
    static func createFrameHeader(finalFrame: Bool, opCode: FrameOpcode, payloadLength: Int, buffer: NSMutableData) {
        
        var bytes: [UInt8] = [(finalFrame ? 0x80 : 0x00) | UInt8(opCode.rawValue), 0, 0,0,0,0,0,0,0,0]
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
        buffer.append(bytes, length: length)
    }
}
