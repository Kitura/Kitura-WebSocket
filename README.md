# Kitura-WebSocket
**WebSocket support for Kitura base servers**

[![Build Status - Master](https://travis-ci.org/IBM-Swift/Kitura-WebSocket.svg?branch=master)](https://travis-ci.org/IBM-Swift/Kitura-WebSocket)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)
&nbsp;[![Slack Status](http://swift-at-ibm-slack.mybluemix.net/badge.svg)](http://swift-at-ibm-slack.mybluemix.net/)

## Summary

Kitura-WebSocket provides Kitura based servers the ability to receive and send messages to clients using the WebSocket
protocol (RFC 6455). It is compatible with a variety of WebSocket clients, including:
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
Working with Kitura-WebSocket requires that you are set up to work with Kitura. See
[www.kitura.io](http://www.kitura.io/en/starter/settingup.html) for details.

## APIs
The following is an overview of the Kitura-WebSocket APIs. For more details see http://ibm-swift.github.io/Kitura-WebSocket.

When using the WebSocket protocol clients connect to WebSocket Services running on a particular server. WebSocket Services are
identified on a particular server via a path. This path is sent in the Upgrade request used to upgrade a connection from
HTTP 1.1 to WebSocket.

The Kitura-WebSocket API reflects that interaction using the class `WebSocketConnection` which represents a WebSocket client's
connection to a service and the protocol `WebSocketService` which is implemented by classes that are WebSocket Services.

A specific `WebSocketConnection` object is connected to a specific `WebSocketService` instance. On the other hand a specific
`WebSocketService` instance is connected to many `WebSocketConnection` objects.

### WebSocketConnection
The WebSocketConnection class provides:
- Functions to send text and binary messages to the client
  ```swift
  WebSocketConnection.send(message: Data)
  WebSocketConnection.send(message: String)
  ```
- Functions to close the connection gracefully and forcefully
  ```swift
  WebSocketConnection.close(reason: WebSocketCloseReasonCode?=nil, description: String?=nil)
  WebSocketConnection.drop(reason: WebSocketCloseReasonCode?=nil, description: String?=nil)
  ```
  In both close() and drop(), the `WebSocketCloseReasonCode` enum provides the standard WebSocket Close Reason codes, with the ability
  to specify application specific ones.

- A unique identifier that can be used to help manage the collection of `WebSocketConnection` objects connected to a `WebSocketService`.
  ```swift
  id: String
  ```

### WebSocketService
The functions of the WebSocketService protocol enable Kitura-WebSocket to notify a WebSocket service of a set of events that
occur. These events include:
- A client has connected to the WebSocketService
```swift
func connected(connection: WebSocketConnection)
```

- A client has disconnected from the WebSocketService
```swift
disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode)
```
The reason parameter contains the reason code associated with the client disconnecting. It may come from either
a close command sent by the client or determined by Kitura-WebSocket if the connection's socket suddenly was closed.

- A binary message was received from a client
```swift
func received(message: Data, from: WebSocketConnection)
```
The message parameter contains the bytes of the message in the form of a Data struct.

- A text message was received from a client
```swift
func received(message: String, from: WebSocketConnection)
```
The message parameter contains the message in the form of a String.

### WebSocket

Classes which implement the `WebSocketService` protocol are registered with the server using the function:
```swift
WebSocket.register(service: WebSocketService, onPath: String)
```
This function is passed the `WebSocketService` being registered along with the path it is being registered on.

## An example
A simple example to better describe the APIs of Kitura-WebSocket. This example, a very simplistic chat service.
The server side is written in Swift using Kitura-WebSocket and the client side is written in JavaScript using
Node.js and the websocket NPM package.

### Pre-requisites
In order to run the client one must have Node.js installed.

### The server
The server, keeps track of the clients that have connected to it and echoes all text messages sent to it to all
of the clients that have connected to it, with the exception of the client that sent the message.

The server's directory setup is something like this:
<pre>
ServerDirectory
├── Package.swift
└── Sources
    └── ChatServer
        ├── ChatService.swift
        └── main.swift
</pre>

The Package.swift file contains:
```swift
import PackageDescription

let package = Package(
    name: "ChatServer",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/HeliumLogger.git", majorVersion: 1, minor: 6),
        .Package(url: "https://github.com/IBM-Swift/Kitura-WebSocket", majorVersion: 0, minor: 7)
    ]
)
```
The HeliumLogger package, while strictly not required, was added to enable logging.

The ChatService.swift file contains:
```swift
// ChatServer is a very simple chat server

import Foundation

import KituraWebSocket

class ChatService: WebSocketService {

    private var connections = [String: WebSocketConnection]()

    public func connected(connection: WebSocketConnection) {
        connections[connection.id] = connection
    }

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {
        connections.removeValue(forKey: connection.id)
    }

    public func received(message: Data, from: WebSocketConnection) {
        from.close(reason: .invalidDataType, description: "Chat-Server only accepts text messages")

        connections.removeValue(forKey: from.id)
    }

    public func received(message: String, from: WebSocketConnection) {
        for (connectionId, connection) in connections {
            if connectionId != from.id {
                connection.send(message: message)
            }
        }
    }
}
```
The class has a Dictionary, connections, which is used to keep track of the connections of all of the connected clients. The Dictionary is
maintained by the `connected` and `disconnected` functions, which are, respectively, adding and removing connections from the dictionary.

The `received` function, which receives binary messages, is rejecting the message, closing the client connection and removing the connection
from the set of known connections.

Lastly, the `received` function, which receives text messages, simply echoes the message received to all clients except the one who sent the message.

The main.swift file contains:
```swift
// ChatServer is a very simple chat server

import Foundation

import KituraNet
import KituraWebSocket

import HeliumLogger
import LoggerAPI

// Using an implementation for a Logger
HeliumLogger.use(.info)

WebSocket.register(service: ChatService(), onPath: "chat")

class ChatServerDelegate: ServerDelegate {
    public func handle(request: ServerRequest, response: ServerResponse) {}
}

// Add HTTP Server to listen on port 8090
let server = HTTP.createServer()
server.delegate = ChatServerDelegate()

do {
    try server.listen(on: 8090)
    ListenerGroup.waitForListeners()
} catch {
    Log.error("Error listening on port 8090: \(error).")
}
```
In the main.swift file:
- The HeliumLogger is set up to log info, warning, and error type messages.
- The ChatService defined in the ChatService.swift file is registered on the path *chat*.
- An HTTP server is created and setup to listen on port 8090.

With this server set up clients should connect to the chat service as *ws://__host__:8090/chat*, where **host** is the host running the server.

### The client
The client has a simple command line interface. At startup one passes the host and port number. The client simply reads
messages to be sent from the terminal and displays messages received on the terminal as well.

The server's directory setup is something like this:
<pre>
ClientDirectory
├── package.json
└── chat.js
</pre>

The package.json at a minimum contains:
```javascript
{
  "name": "chat",
  "description": "Simple chat server client",
  "version": "0.0.1",
  "engines": {
    "node": ">=0.8.0"
  },
  "dependencies": {
    "websocket": "^1.0.23"
  }
}
```

The chat.js file contains:
```javascript
/* main file of Simple Chat Server Client */

var readline = require('readline');
var WebSocketClient = require('websocket').client

var host = process.argv[2];

rl = readline.createInterface(process.stdin, process.stdout);

rl.setPrompt('> ');
rl.prompt();
var client = new WebSocketClient();

client.on('connectFailed', function(error) {
    console.log('Connect Error: ' + error.toString());
    process.exit();
});

client.on('connect', function(connection) {
    connection.on('error', function(error) {
        console.log("Connection Error: " + error.toString());
        process.exit();
    });

    connection.on('close', function(reasonCode, description) {
        console.log('chat Connection Closed. Code=' + reasonCode + ' (' + description +')');
    });

    connection.on('message', function(message) {
        if (message.type === 'utf8') {
            console.log('\r=> ' + message.utf8Data);
            rl.prompt();
        }   
    });

    rl.on('line', function(line) {
        connection.sendUTF(line);
        rl.prompt();
    });

    rl.on('close', function() {
        connection.close();
        console.log('Have a great day!');
        process.exit(0);
    });

    rl.prompt();
});

client.connect("ws://" + host +"/chat", "chat");
```

### Building and running the example
To build and run the server, in the server directory, simply:
```
swift build
.build/debug/ChatServer
```
The server is now up and running.

### Setting up and running the client
To setup the client, in the client directory, simply:
```
npm installed
```
That will install the websocket package.

To run the client, again in the client directory, run:
```
node chat.js host:8090
```
Where **host** is the hostname of the host on which the server is running.

The client can be run in several terminal windows on the same computer.
## Community

We love to talk server-side Swift, and Kitura. Join our [Slack](http://swift-at-ibm-slack.mybluemix.net/) to meet the team!

## License
This library is licensed under Apache 2.0. Full license text is available in [LICENSE](LICENSE.txt).
