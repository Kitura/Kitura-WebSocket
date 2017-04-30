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

import Foundation

import KituraNet
import LoggerAPI

/// The implementation of the `IncomingSocketProcessor` protocol for the WebSocket protocol.
/// Receives data from the `IncomingSocketHandler` for a specific socket and provides APIs
/// upwards for sending data to the client over the socket.
class WSSocketProcessor: IncomingSocketProcessor {
    /// A back reference to the `IncomingSocketHandler` processing the socket that
    /// this `IncomingDataProcessor` is processing.
    public weak var handler: IncomingSocketHandler? {
        didSet {
            guard handler != nil else { return }
            connection.fireConnected()
        }
    }
    
    /// The socket if idle will be kept alive until...
    public var keepAliveUntil: TimeInterval = 500.0
    
    /// A flag to indicate that the socket has a request in progress
    public var inProgress = true
    
    private var parser = WSFrameParser()
    
    private var byteIndex = 0
    
    private let connection: WebSocketConnection
    
    init(connection: WebSocketConnection) {
        self.connection = connection
    }
    
    /// Process data read from the socket.
    ///
    /// - Parameter buffer: An NSData object containing the data that was read in
    ///                    and needs to be processed.
    ///
    /// - Returns: true if the data was processed, false if it needs to be processed later.
    public func process(_ buffer: NSData) -> Bool {
        let length = buffer.length
        
        while byteIndex < length {
            let (completed, error, bytesConsumed) = parser.parse(buffer, from: byteIndex)
        
            guard error == nil else {
                // What should be done if there is an error?
                Log.error("Error parsing frame. \(error!)")
                connection.close(reason: .protocolError, description: error?.description)
                return true
            }
            
            if bytesConsumed == 0 {
                break
            }
        
            byteIndex += bytesConsumed
        
            if completed {
                connection.received(frame: parser.frame)
                parser.reset()
            }
        }
        
        let finishedBuffer: Bool
        if byteIndex >= length {
            finishedBuffer = true
            byteIndex = 0
        }
        else {
            finishedBuffer = false
        }
        return finishedBuffer
    }
    
    /// Write data to the socket
    ///
    /// - Parameter from: An NSData object containing the bytes to be written to the socket.
    public func write(from data: NSData) {
        handler?.write(from: data)
    }
    
    /// Write a sequence of bytes in an array to the socket
    ///
    /// - Parameter from: An UnsafeRawPointer to the sequence of bytes to be written to the socket.
    /// - Parameter length: The number of bytes to write to the socket.
    public func write(from bytes: UnsafeRawPointer, length: Int) {
        handler?.write(from: bytes, length: length)
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    public func close() {
        handler?.prepareToClose()
    }
    
    /// Called by the `IncomingSocketHandler` to tell us that the socket has been closed.
    public func socketClosed() {
        connection.connectionClosed(reason: .noReasonCodeSent)
    }
}
