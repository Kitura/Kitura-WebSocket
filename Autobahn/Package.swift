// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "WebSocketEchoServer",
    dependencies: [
         .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.8.0"),
         .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", from: "1.7.0"),
         .package(url: "https://github.com/IBM-Swift/Kitura-WebSocket.git", from: "2.0.0")
    ],
    targets: [
    .target(
        name: "WebSocketEchoServer",
        dependencies: ["Kitura", "HeliumLogger", "Kitura-WebSocket"]),
    ]
)
