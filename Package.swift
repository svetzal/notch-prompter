// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchPrompterKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NotchPrompterKit", targets: ["NotchPrompterKit"])
    ],
    targets: [
        .target(name: "NotchPrompterKit"),
        .testTarget(name: "NotchPrompterKitTests", dependencies: ["NotchPrompterKit"])
    ]
)
