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
import CZlib
import NIOWebSocket

// Implementation of `PermessageDeflateDecompressor` a `ChannelInboundHandler` that intercepts incoming WebSocket frames, inflating the payload and
// writing the new frames back to the channel, to be eventually received by WebSocketConnection.

// Some parts of this code are derived from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
class PermessageDeflateDecompressor : ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame 
    typealias InboundOut = WebSocketFrame

    init(maxWindowBits: Int32 = 15, noContextTakeOver: Bool = false) {
        self.maxWindowBits = maxWindowBits
        self.noContextTakeOver = noContextTakeOver
    }

    var noContextTakeOver: Bool

    // The zlib stream
    private var stream: z_stream = z_stream()

    // A buffer to accumulate payload across multiple frames
    var payload: ByteBuffer?

    // Is this a text or binary message? Continuation frames don't have this information.
    private var messageType: WebSocketOpcode?

    // The default LZ77 window size; 15
    var maxWindowBits = MAX_WBITS

    // PermessageDeflateDecompressor is a `ChannelInboundHandler`, this function gets called when the previous inbound handler fires a channel read event.
    // Here, we intercept incoming compressed frames, decompress the payload across multiple continuation frame and write a fire a channel read event
    // with the entire frame data decompressed.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var frame = unwrapInboundIn(data)
        // If this is a control frame, there's nothing to do.
        guard frame.opcode == .text || frame.opcode == .binary || frame.opcode == .continuation else {
            context.fireChannelRead(self.wrapInboundOut(frame))
            return
        }

        // If this is a continuation frame, have the payload appended to `payload`, else set `payload` and store the messageType
        var receivedPayload = frame.unmaskedData
        if frame.opcode == .continuation {
            self.payload?.writeBuffer(&receivedPayload)
        } else {
            self.messageType = frame.opcode
            self.payload = receivedPayload
        }

        // If the current frame isn't a final frame of a message or if `payload` still empty, there's nothing to do.
        guard frame.fin, var inputBuffer = self.payload else { return }

        // Append the trailer 0, 0, ff, ff before decompressing
        inputBuffer.writeBytes([0x00, 0x00, 0xff, 0xff])
        var inflatedPayload = inflatePayload(in: inputBuffer, allocator: context.channel.allocator)

        // Apply the WebSocket mask on the inflated payload
        inflatedPayload.webSocketMask(frame.maskKey!)

        // Create a new frame with the inflated payload and pass it on to the next inbound handler, mostly WebSocketConnection
        let inflatedFrame = WebSocketFrame(fin: true, rsv1: false, opcode: self.messageType!, maskKey: frame.maskKey!, data: inflatedPayload)
        context.fireChannelRead(self.wrapInboundOut(inflatedFrame))
    }

    func inflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator) -> ByteBuffer {
        // Initialize the inflater as per https://www.zlib.net/zlib_how.html
        stream.zalloc = nil 
        stream.zfree = nil 
        stream.opaque = nil 
        stream.avail_in = 0 
        stream.next_in = nil 
        let rc = inflateInit2_(&stream, -self.maxWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")

        defer {
            // Deinitialize before returning
            inflateEnd(&stream)
        }

        // Inflate/decompress the payload
        return decompressPayload(in: buffer, allocator: allocator, flag: Z_SYNC_FLUSH)
    }

    func decompressPayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, flag: Int32) -> ByteBuffer {
        var inputBuffer = buffer
        guard inputBuffer.readableBytes > 0 else {
            // TODO: Log an error
            return buffer
        }
        let payloadSize =  inputBuffer.readableBytes
        var outputBuffer = allocator.buffer(capacity: 2) // starting with a small capacity hint

        // Decompression may happen in steps, we'd need to continue calling inflate() until there's no available input
        repeat {
            var partialOutputBuffer = allocator.buffer(capacity: inputBuffer.readableBytes)
            stream._inflate(from: &inputBuffer, to: &partialOutputBuffer, flag: flag)
            // calculate the number of bytes processed
            let processedBytes = payloadSize - Int(stream.avail_in)
            // move the reader index
            inputBuffer.moveReaderIndex(to: processedBytes)
            // append partial output to the ouput buffer
            outputBuffer.writeBuffer(&partialOutputBuffer)
        } while stream.avail_in > 0
        return outputBuffer 
    }
}

// This code is derived from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
extension z_stream {
    // Executes inflate from one buffer to another buffer.
    mutating func _inflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr, count: dataPtr.count)
            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!
            let rc = inflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "Decompression failed: \(rc)")
            if rc == Z_STREAM_END {
                inflateEnd(&self)
            }
            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    // A private function that sets the inflate target buffer and then calls inflate.
    // This relies on having the input set by the previous caller: it will use whatever input was
    // configured.
    private mutating func inflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK

        buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = inflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }
        return rc
    }
}
