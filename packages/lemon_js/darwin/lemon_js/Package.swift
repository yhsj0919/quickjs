// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "lemon_js",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0")
    ],
    products: [
        .library(name: "lemon-js", targets: ["lemon_js"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "lemon_js_native",
            cSettings: [
                .define("_GNU_SOURCE"),
                .define("QUICKJS_BUILD"),
                .define("QUICKJS_BRIDGE_BUILD")
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "lemon_js",
            dependencies: [
                "lemon_js_native",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
