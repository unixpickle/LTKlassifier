// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "LTKlassifier",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "LTKLabel", targets: ["LTKLabel"]),
    .library(name: "LTKModel", targets: ["LTKModel"]),
    .library(name: "ImageUtils", targets: ["ImageUtils"]),
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
        "LTKLabel", "LTKModel", "ImageUtils", .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
        .product(name: "SQLite", package: "sqlite.swift"),
      ]
    ),
    .target(
      name: "ImageUtils",
      dependencies: [
        .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
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
    .executableTarget(
      name: "ClassifyUI",
      dependencies: [
        "LTKModel", "LTKLabel", "ImageUtils", .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
  ]
)
