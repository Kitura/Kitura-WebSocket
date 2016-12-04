# Kitura-WebSocket
**WebSocket support for Kitura base servers**

![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)
&nbsp;[![Slack Status](http://swift-at-ibm-slack.mybluemix.net/badge.svg)](http://swift-at-ibm-slack.mybluemix.net/)

## Summary

Kitura-WebSocket provides Kitura based servers the ability to receive and send messages to clients using the WebSocket protocol (RFC 6455). It is compatible with a variety of WebSocket clients, including:
- The builtin WebSocket support in the Chrome, FireFox, and Safari browsers
- The NPM [websocket](https://www.npmjs.com/package/websocket) package.

Kitura-WebSocket supports version thirteen of the WebSocket protocol.

## Table of Contents
* [Summary](#summary)
* [Pre-requisites](#pre-requisites)
* [APIs](#apis)
* [An example](#an-example)
* [Community](#community)
* [License](#license)

## Pre-requisites
Working with Kitura-WebSocket requires that you are set up to work with Kitura. See [www.kitura.io](http://www.kitura.io/en/starter/settingup.html) for details.

## APIs
When using the WebSocket protocol clients connect to WebSocket Services running on a particular server. WebSocket Services are identified on a particular server via a path. This path is sent in the Upgrade request used to upgrade a connection fro HTTP 1.1 to WebSocket.

The Kitura-WebSocket API models that interaction using the class `WebSocketClient` which represents WebSocket client connections and the protocol `WebSocketService` which is implemented by classes that are WebSocket Services. A specific `WebSocketClient` object is connected to a specific `WebSocketService` instance. On the other hand a specific `WebSocketService` instance is connected to many `WebSocketClient` objects.

### WebSocketClient
The WebSocketClient class provides:
- Functions to send text and binary messages to the client
  ```swift
  WebSocketClient.send(message: Data)
  WebSocketClient.send(message: String)
  ```
- Functions to close the connection gracefully and forcefully
  ```swift
  WebSocketClient.close(reason: WebSocketCloseReasonCode?=nil, description: String?=nil)
  WebSocketClient.drop(reason: WebSocketCloseReasonCode?=nil, description: String?=nil)
  ```
  In both close() and drop(), the `WebSocketCloseReasonCode` enum provides the standard WebSocket Close Reason codes, with the ability to specify application specific ones.

- A unique identifier that can be used to help manage the collection of `WebSocketClient` objects connected to a `WebSocketService`.
  ```swift
  id: String
  ```

### WebSocketService

### WebSocket

Classes which implement the `WebSocketService` protocol are registered with the server using the function:
```swift
WebSocket.register(service: WebSocketService, onPath: String)
```
This function is passes the `WebSocketService` being registered along with the path it is being registered on.

## An example

## Community

We love to talk server-side Swift, and Kitura. Join our [Slack](http://swift-at-ibm-slack.mybluemix.net/) to meet the team!

## License
This library is licensed under Apache 2.0. Full license text is available in [LICENSE](LICENSE.txt).
