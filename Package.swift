// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMQuickJS",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "MQuickJS",
            targets: ["MQuickJS"]
        ),
    ],
    targets: [
        // C library target - mquickjs engine
        .target(
            name: "CMQuickJS",
            path: "Sources/CMQuickJS",
            sources: [
                "mquickjs.c",
                "cutils.c",
                "libm.c",
                "dtoa.c",
                "mqjs_bridge.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("CONFIG_VERSION", to: "\"2025-01-14\""),
                .define("_GNU_SOURCE"),
                // Optimize for size in release builds (embedded use case)
                .unsafeFlags(["-Os"], .when(configuration: .release))
            ]
        ),

        // Swift wrapper target
        .target(
            name: "MQuickJS",
            dependencies: ["CMQuickJS"],
            path: "Sources/MQuickJS"
        ),

        // Test target
        .testTarget(
            name: "MQuickJSTests",
            dependencies: ["MQuickJS"]
        ),
    ],
    cLanguageStandard: .c11
)
