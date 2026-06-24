// swift-tools-version:5.9
import PackageDescription

// swift-libplist — libplist 2.7.0 packaged as a binary Swift Package.
//
// The `plist` product is backed by a prebuilt XCFramework containing static
// libraries for macOS and iOS (device + simulator). The Clang module map inside
// the framework exposes the C API, so consumers can either:
//
//     import plist                 // Swift
//     #include <plist/plist.h>     // C / Objective-C(++)
//
let package = Package(
    name: "swift-libplist",
    platforms: [
        .macOS(.v11),
        .iOS(.v13)
    ],
    products: [
        .library(name: "plist", targets: ["plist"])
    ],
    targets: [
        .binaryTarget(
            name: "plist",
            path: "plist.xcframework"
        )
    ]
)
