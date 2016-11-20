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

/// The `WebSocketCloseReasonCode` enum defines the set of reason codes that a
/// WebSocket application can send/receive when a connection is closed.
public enum WebSocketCloseReasonCode {
    /// Closed abnormally (1006)
    case closedAbnormally
    
    /// An extension was missing that was required (1010)
    case extensionMissing
    
    /// Server is going away (1001)
    case goingAway
    
    /// Data within a message was invalid (1007)
    case invalidDataContents
    
    /// Message was of the incorrect type (binary/text) (1003)
    case invalidDataType
    
    /// Message was too large (1009)
    case messageTooLarge
    
    /// Closed normally (1000)
    case normal
    
    /// No reason code sent with the close request (1005)
    case noReasonCodeSent
    
    /// A policy violation occurred (1008)
    case policyViolation
    
    /// A protocol error occurred (1002)
    case protocolError
    
    /// The server had an error with the request (1011)
    case serverError
    
    /// This reson code is used to send application defined reason codes.
    case userDefined(Int16)
    
    /// Get the sixteen bit integer code for a WebSocketCloseReasonCode instance
    public func code() -> Int16 {
        switch self {
        case .closedAbnormally: return 1006
        case .extensionMissing: return 1010
        case .goingAway: return 1001
        case .invalidDataContents: return 1007
        case .invalidDataType: return 1003
        case .messageTooLarge: return 1009
        case .normal: return 1000
        case .noReasonCodeSent: return 1005
        case .policyViolation: return 1008
        case .protocolError: return 1002
        case .serverError: return 1011
        case .userDefined(let userCode): return userCode
        }
    }
    
    /// Convert a sixteen bit WebSocket close frame reason code to a WebSocketCloseReasonCode instance 
    public static func from(code reasonCode: Int16) -> WebSocketCloseReasonCode {
        switch reasonCode {
        case 1000: return .normal
        case 1001: return .goingAway
        case 1002: return .protocolError
        case 1003: return .invalidDataType
        case 1005: return .noReasonCodeSent
        case 1006: return .closedAbnormally
        case 1007: return .invalidDataContents
        case 1008: return .policyViolation
        case 1009: return .messageTooLarge
        case 1010: return .extensionMissing
        case 1011: return .serverError
        default:
            return .userDefined(reasonCode)
        }
    }
}
