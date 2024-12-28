// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "LTKlassifier",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "LTKModel", targets: ["LTKModel"]),
    .library(name: "LTKData", targets: ["LTKData"]),
  ],
  dependencies: [
    .package(url: "https://github.com/unixpickle/honeycrisp", from: "0.0.19"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "LTKModel",
      dependencies: [
        .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
    .target(
      name: "LTKData",
      dependencies: [
        "LTKModel", .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
    .executableTarget(
      name: "TrainLTK",
      dependencies: [
        "LTKModel", "LTKData", .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Honeycrisp", package: "honeycrisp"),
        .product(name: "HCBacktrace", package: "honeycrisp"),
      ]
    ),
  ]
)
