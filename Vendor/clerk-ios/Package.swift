// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Clerk",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v17),
    .macCatalyst(.v17),
    .macOS(.v14),
    .watchOS(.v10),
    .tvOS(.v17),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "ClerkKit", targets: ["ClerkKit"]),
    .library(name: "ClerkKitUI", targets: ["ClerkKitUI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/kean/Nuke.git", .upToNextMajor(from: "13.0.6")),
    .package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit", .upToNextMajor(from: "5.0.0")),
  ],
  targets: [
    .target(
      name: "ClerkKit",
      dependencies: [],
      path: "Sources/ClerkKit",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
      ]
    ),
    .target(
      name: "ClerkKitUI",
      dependencies: [
        "ClerkKit",
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
      ],
      path: "Sources/ClerkKitUI",
      resources: [
        .process("Resources"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
      ]
    ),
  ]
)
