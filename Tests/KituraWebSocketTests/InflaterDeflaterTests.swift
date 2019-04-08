/**
 * Copyright IBM Corporation 2019
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
import Foundation
import NIO
import CZlib

@testable import KituraWebSocket

class InflaterDeflaterTests: KituraTest {

    static var allTests: [(String, (InflaterDeflaterTests) -> () throws -> Void)] {
        return [
            ("testDeflateAndInflateWithString", testDeflateAndInflateWithString),
            ("testDeflateAndInflateWithBytes", testDeflateAndInflateWithBytes),
        ]
    }

    func testDeflateAndInflateWithString() {
        testWithString("a")
        testWithString("xy")
        testWithString("abc")
        testWithString("abcd")
        testWithString("0000")
        testWithString("skfjsdlkjfldkjioroi32j423kljl213kj4lk32j4lk2j4kl32j4lk32j4lk3242")
        testWithString("0000000000000000000000000000000000000000000000000000")
        testWithString("1nkp12p032nn1l1o1knfk;0i0nju]ijijkjkj1121212100000000000000000fsfefdf12121212121fdgfgfgfgfgf")
        testWithString("abcdefghijklmnopqrstuvwxyz0123456789")
        testWithString(String(repeating: "quick brown fox jumps over the lazy dog", count: 100))
    }

    func testDeflateAndInflateWithBytes() {
         let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
         var buffer = ByteBufferAllocator().buffer(capacity: 1)
         var count = 0
         repeat {
             buffer.writeBytes(bytes)
             count += 1
         } while count < 100000

         //deflate
         let deflater = PermessageDeflateCompressor()
         let deflatedBuffer = deflater.deflatePayload(in: buffer, allocator: ByteBufferAllocator())

         //inflate
         let inflater = PermessageDeflateDecompressor()
         let inflatedBuffer = inflater.inflatePayload(in: deflatedBuffer, allocator: ByteBufferAllocator())

         //test
         XCTAssertEqual(buffer, inflatedBuffer)
    }


    func testWithString(_ input: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: 1)
        buffer.writeString(input)

        //deflate
        let deflater = PermessageDeflateCompressor()
        let deflatedBuffer = deflater.deflatePayload(in: buffer, allocator: ByteBufferAllocator())

        //inflate
        let inflater = PermessageDeflateDecompressor()
        var inflatedBuffer = inflater.inflatePayload(in: deflatedBuffer, allocator: ByteBufferAllocator())
        let output = inflatedBuffer.readString(length: inflatedBuffer.readableBytes)
 
        //test   
        XCTAssertEqual(output, input)
    }
         
}
