# WebSockets Autobahn-Testsuite

This document will take you through the steps to test Kitura-Websockets using [autobahn-testsuite](https://github.com/crossbario/autobahn-testsuite).

### Convenience (ready-to-run) Docker implementation

For convenience, a project is provided in `Autobahn/` that implements the code below.

A script `Autobahn/run.sh` is included that will build this within a Docker container, run the container, and then run the autobahn test suite (in client mode) against this server.

### Creating a EchoServer
These tests are run against a WebSocket EchoServer so we must first set one up.

1. Create a swift project:
```
mkdir ~/WebSocketEchoServer
cd ~/WebSocketEchoServer
swift package init --type executable
open Package.swift
```

2. Inside the `Package.swift` replace the text with:
```swift
// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "WebSocketEchoServer",
    dependencies: [
         .package(url: "https://github.com/Kitura/Kitura.git", from: "2.3.0"),
         .package(url: "https://github.com/Kitura/HeliumLogger.git", .upToNextMinor(from: "1.7.0")),
         .package(url: "https://github.com/Kitura/Kitura-WebSocket.git", from: "2.0.0")
    ],
    targets: [
    .target(
        name: "WebSocketEchoServer",
        dependencies: ["Kitura", "HeliumLogger", "Kitura-WebSocket"]),
    ]
)
```
3. Open the projects main.swift file:
```
open ~/WebSocketEchoServer/Sources/WebSocketEchoServer/main.swift
```
4. Inside the `main.swift` file replace `print("Hello, world!")` with:
```swift
import Foundation
import Kitura
import KituraWebSocket
import HeliumLogger

// Using an implementation for a Logger
HeliumLogger.use(.info)

let router = Router()

WebSocket.register(service: EchoService(), onPath: "/")

let port = 9001

Kitura.addHTTPServer(onPort: port, with: router)
Kitura.run()
```
5. Create the `EchoService` file
```
cd ~/WebSocketEchoServer/Sources/WebSocketEchoServer/
touch EchoService.swift
open EchoService.swift
```
6. Inside `EchoService` add the following code:
```swift
import Foundation

import KituraWebSocket
import LoggerAPI

class EchoService: WebSocketService {

    public func connected(connection: WebSocketConnection) {}

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {}

    public func received(message: Data, from: WebSocketConnection) {
        from.send(message: message)
    }

    public func received(message: String, from: WebSocketConnection) {
        Log.info("Got message \(message)... sending it back")
        from.send(message: message)
    }
}
```
7. Start the EchoServer:
```
cd ~/WebSocketEchoServer
swift build
.build/x86_64-apple-macosx10.10/debug/WebSocketEchoServer
```

### Install and run the test suite
Open a new terminal window and enter:
```
pip install autobahntestsuite
cd ~
mkdir testAutobahn
cd testAutobahn
wstest -m fuzzingclient
```

This will run the autobahn tests against a server running on port 9001.
To change the tests inside `testAutobahn`:
`open fuzzingclient.json`

In here you can select specific tests to include or exclude.

To view the results `open ~/testAutobahn/reports/servers/index.html`
