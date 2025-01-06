// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "LTKlassifier",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "LTKLabel", targets: ["LTKLabel"]),
    .library(name: "LTKModel", targets: ["LTKModel"]),
    .library(name: "LTKData", targets: ["LTKData"]),
  ],
  dependencies: [
    .package(url: "https://github.com/unixpickle/honeycrisp", from: "0.0.19"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
  ],
  targets: [
    .target(name: "LTKLabel", dependencies: []),
    .target(
      name: "LTKModel",
      dependencies: [
        "LTKLabel", .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
    .target(
      name: "LTKData",
      dependencies: [
        "LTKLabel", "LTKModel", .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
        .product(name: "SQLite", package: "sqlite.swift"),
      ]
    ),
    .executableTarget(
      name: "TrainLTK",
      dependencies: [
        "LTKModel", "LTKData", "LTKLabel",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
  ]
)
