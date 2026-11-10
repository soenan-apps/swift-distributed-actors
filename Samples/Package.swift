// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

internal var globalSwiftSettings: [SwiftSetting]

internal var globalConcurrencyFlags: [String] = [
    "-Xfrontend", "-disable-availability-checking"
]

globalSwiftSettings = [
    SwiftSetting.unsafeFlags(globalConcurrencyFlags)
]

internal var targets: [PackageDescription.Target] = [
    // ==== Samples ====
    // MARK: Samples

    .executableTarget(
        name: "SampleDiningPhilosophers",
        dependencies: [
            .product(name: "DistributedCluster", package: "swift-distributed-actors")
        ],
        path: "Sources/SampleDiningPhilosophers",
        exclude: [
            "dining-philosopher-fsm.graffle",
            "dining-philosopher-fsm.svg",
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ]
    ),
]

internal var dependencies: [Package.Dependency] = [
    // ~~~~~~~     parent       ~~~~~~~
    .package(name: "swift-distributed-actors", path: "../")

    // ~~~~~~~ only for samples ~~~~~~~
]

internal let kPackage: Package = Package(
    name: "swift-distributed-actors-samples",
    platforms: [
        // we require the 'distributed actor' language and runtime feature:
        .iOS(.v17),
        .macOS(.v15),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        // ---  samples ---

        .executable(
            name: "SampleDiningPhilosophers",
            targets: ["SampleDiningPhilosophers"]
        ),
    ],

    dependencies: dependencies,

    targets: targets.map { target in
        var swiftSettings: [SwiftSetting] = target.swiftSettings ?? []
        if target.type != .plugin {
            swiftSettings.append(contentsOf: globalSwiftSettings)
        }
        if !swiftSettings.isEmpty {
            target.swiftSettings = swiftSettings
        }
        return target
    },

    cxxLanguageStandard: .cxx11
)
