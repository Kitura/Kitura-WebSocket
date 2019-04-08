/*
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
 */

import NIO
import NIOWebSocket
import CZlib

// Implementation of a deflater using zlib. This ChannelOutboundHandler acts like an interceptor, consuming original frames written by
// WebSocketConnection, compressing the payload and writing the new frames with a compressed payload onto the channel.

// Some of the code here is borrowed from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
class PermessageDeflateCompressor : ChannelOutboundHandler {
    typealias OutboundIn = WebSocketFrame 
    typealias OutboundOut = WebSocketFrame 

    init(maxWindowBits: Int32 = 15, noContextTakeOver: Bool = false) {
        self.maxWindowBits = maxWindowBits
        self.noContextTakeOver = noContextTakeOver
    }

    var noContextTakeOver: Bool

    // The default LZ77 window value; 15
    var maxWindowBits = MAX_WBITS

    // A buffer that accumulates payload data across multiple frames
    var payload: ByteBuffer?

    private var messageType: WebSocketOpcode?

    // The zlib stream
    private var stream: z_stream = z_stream()

    // PermessageDeflateCompressor is an outbound handler, this function gets called when a frame is written to the channel by WebSocketConnection.
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var frame = unwrapOutboundIn(data)

        // If this is a control frame, do not attempt compression.
        guard frame.opcode == .text || frame.opcode == .binary || frame.opcode == .continuation else {
             context.writeAndFlush(self.wrapOutboundOut(frame)).whenComplete { _ in
                 promise?.succeed(())
             }
             return
        }

        // If this is a continuation frame, have the frame data appended to `payload`, else set payload to frame data.
        if frame.opcode == .continuation {
            self.payload?.writeBuffer(&frame.data)
        } else {
            self.payload = frame.data
            self.messageType = frame.opcode
        }

        // If the current frame isn't the final frame or if payload is empty, there's nothing to do.
        guard frame.fin, let payload = payload else { return }

        // Compress the payload
        let deflatedPayload = deflatePayload(in: payload, allocator: context.channel.allocator, dropFourTrailingOctets: true)

        // Create a new frame with the compressed payload, the rsv1 bit must be set to indicate compression
        let deflatedFrame = WebSocketFrame(fin: frame.fin, rsv1: true, opcode: self.messageType!, maskKey: frame.maskKey, data: deflatedPayload)

        // Write the new frame onto the pipeline
        _ = context.writeAndFlush(self.wrapOutboundOut(deflatedFrame))
    }

    func deflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, dropFourTrailingOctets: Bool = false) -> ByteBuffer {
        // Initialize the deflater as per https://www.zlib.net/zlib_how.html
        stream.zalloc = nil 
        stream.zfree = nil 
        stream.opaque = nil 

        let rc = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, self.maxWindowBits, 8,
                     Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")

        defer {
            // Deinitialize the deflater before returning
            deflateEnd(&stream)
        }

        // Deflate/compress the payload
        return compressPayload(in: buffer, allocator: allocator, flag: Z_SYNC_FLUSH, dropFourTrailingOctets: dropFourTrailingOctets)
    }

    private func compressPayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, flag: Int32, dropFourTrailingOctets: Bool = false) -> ByteBuffer {
        var inputBuffer = buffer
        guard inputBuffer.readableBytes > 0 else {
            //TODO: Log an error message
            return inputBuffer
        }

        // Allocate an output buffer, with a size hint equal to the input (there's no other derivable value for this)
        let bufferSize = Int(deflateBound(&stream, UInt(inputBuffer.readableBytes)))
        var outputBuffer = allocator.buffer(capacity: bufferSize)

        // Compress the payload
        stream._deflate(from: &inputBuffer, to: &outputBuffer, flag: flag)

        // Make sure all of inputBuffer was read, and outputBuffer isn't empty
        precondition(inputBuffer.readableBytes == 0)
        precondition(outputBuffer.readableBytes > 0)

        // Remove the 0x78 0x9C zlib header added by zlib
        _ = outputBuffer.readBytes(length: 2)
        outputBuffer.discardReadBytes()

        // Ignore the 0, 0, 0xff, 0xff trailer added by zlib
        if dropFourTrailingOctets {
            outputBuffer = outputBuffer.getSlice(at: 0, length: outputBuffer.readableBytes-4) ?? outputBuffer
        }

        return outputBuffer
    }
}

// This code is borrowed from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
private extension z_stream {
    // Executes deflate from one buffer to another buffer. The advantage of this method is that it
    // will ensure that the stream is "safe" after each call (that is, that the stream does not have
    // pointers to byte buffers any longer).
    mutating func _deflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        defer {
            // Per https://www.zlib.net/zlib_how.html
            self.avail_in = 0
            self.next_in = nil
            self.avail_out = 0
            self.next_out = nil
        }

        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr,
                                                          count: dataPtr.count)

            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!

            let rc = deflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "Deflate failed: \(rc)")

            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    // A private function that sets the deflate target buffer and then calls deflate.
    // This relies on having the input set by the previous caller: it will use whatever input was
    // configured.
    private mutating func deflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK

        buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = deflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }

        return rc
    }
}
