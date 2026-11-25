// swift-tools-version: 5.7
import PackageDescription

// 本轮 GitHub Release 的 Tag；每次发布时与远端版本名称保持一致。
let releaseVersion = "4.7.4"

// 三个附件共用的下载目录；Release 和附件公开发布后才可访问。
let releaseBaseURL = "https://github.com/ZCSDK/SobotClientSDK-SPM/releases/download/\(releaseVersion)"

// 远程预发布清单：checksum 对应本轮生成的三个 ZIP，重新压缩后需重新计算。
let package = Package(
    name: "SobotClientSDK",
    platforms: [.iOS(.v15)],
    products: [
        // 客户选择一个产品，即可获得全部业务模块和资源适配入口。
        .library(
            name: "SobotClientSDK",
            targets: ["SobotKit", "SobotChatClient", "SobotCommon", "SobotClientSDKResources"]
        )
    ],
    targets: [
        // Common：使用本轮 Release 附件及其真实 ZIP 校验值。
        .binaryTarget(
            name: "SobotCommon",
            url: "\(releaseBaseURL)/SobotCommon.xcframework.zip",
            checksum: "2d8baa90ae12c250a04dbf6f02071ba655afceb1426e175332777b5114aff22e"
        ),
        // ChatClient：校验值只对应本轮生成的同名 ZIP。
        .binaryTarget(
            name: "SobotChatClient",
            url: "\(releaseBaseURL)/SobotChatClient.xcframework.zip",
            checksum: "9f8205b90e01a97f439760d019d805bd8453b482641a4a8a1eaef20b6b687dab"
        ),
        // Kit：保留原模块名，下载位置随 releaseVersion 更新。
        .binaryTarget(
            name: "SobotKit",
            url: "\(releaseBaseURL)/SobotKit.xcframework.zip",
            checksum: "c8ec877d0d8b1c69413c3cf0ae3989ffdf25a983e82138b435b00fd5e43e58c6"
        ),
        // Objective-C 资源模块同时提供 Swift 可调用的公开接口。
        .target(
            name: "SobotClientSDKResources",
            dependencies: ["SobotCommon", "SobotChatClient", "SobotKit"],
            path: "Sources/SobotClientSDKResources",
            resources: [
                .copy("Resources/SobotKit.bundle"),
                // 复用同版本 Pod 发布包的隐私清单，放入 SPM 资源 Bundle 根目录。
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            publicHeadersPath: "include",
            linkerSettings: [
                // SobotKit 的 HTML 解析代码依赖系统 libxml2。
                .linkedLibrary("xml2")
            ]
        )
    ]
)
