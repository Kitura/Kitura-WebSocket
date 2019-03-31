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

// An extension that implements WebSocket compression through the permessage-deflate algorithm
// RFC 7692: https://tools.ietf.org/html/rfc7692

class PermessageDeflate: WebSocketProtocolExtension {

    // Returns the deflater and inflater, to be subsequently added to the channel pipeline
    func handlers(header: String) -> [ChannelHandler] {
        guard header.hasPrefix("permessage-deflate") else { return [] }
        var deflaterMaxWindowBits: Int32 = 15
        var inflaterMaxWindowBits: Int32 = 15
        var clientNoContextTakeover = false
        let serverNoContextTakeover = false //TODO: `let` for now, needs to be a `var` when we start handling this parameter

        // Four parameters to handle:
        // * server_max_window_bits: the LZ77 sliding window size used by the server for compression
        // * client_max_window_bits: the LZ77 sliding window size used by the server for decompression
        // * server_no_context_takeover: prevent the server from using context-takeover
        // * client_no_context_takeover: prevent the client from using context-takeover
        for parameter in header.components(separatedBy: "; ") {
            // If we receieved a valid value for server_max_window_bits, configure the deflater to use it
            if parameter.hasPrefix("server_max_window_bits") {
                let maxWindowBits = parameter.components(separatedBy: "=")
                guard maxWindowBits.count == 2 else { continue }
                if let mwBits = Int32(maxWindowBits[1]) {
                    if mwBits >= 8 && mwBits <= 15 {
                        deflaterMaxWindowBits = mwBits
                    }
                }
            }

            // If we receieved a valid value for server_max_window_bits, configure the inflater to use it
            if parameter.hasPrefix("client_max_window_bits") {
                let maxWindowBits = parameter.components(separatedBy: "=")
                guard maxWindowBits.count == 2 else { continue }
                if let mwBits = Int32(maxWindowBits[1]) {
                    if mwBits >= 8 && mwBits <= 15  {
                        inflaterMaxWindowBits = mwBits
                    }
                }
            }

            //TODO: If server_no_context_takeover was received, do we create new inflater/deflater objects?
            if parameter == "client_no_context_takeover" {
                clientNoContextTakeover = true
            }
        }

        return [PermessageDeflateCompressor(maxWindowBits: deflaterMaxWindowBits, noContextTakeOver: serverNoContextTakeover),
                   PermessageDeflateDecompressor(maxWindowBits: inflaterMaxWindowBits, noContextTakeOver: clientNoContextTakeover)]
    }

    // Comprehend the Sec-WebSocket-Extensions request header and build a response header
    // In this context, the specification is not really very strict.
    func negotiate(header: String) -> String {
        var response = "permessage-deflate"

        // This shouldn't be really possible. We reached here only because the header was used to fetch the PerMessageDeflate implementation.
        guard header.hasPrefix("permessage-deflate") else { return response }

        for parameter in header.components(separatedBy: "; ") {
            if parameter == "client_no_context_takeover" {
                response.append("; \(parameter)")
            }
        }
        return response
    }
}
