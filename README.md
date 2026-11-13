# SobotClientSDK-SPM
Swift Package Manager distribution for Sobot iOS SDK

当前已配置 **SPM 4.7.3-beta.1 的远程二进制地址和真实 checksum**，本次修改未执行 Git 提交、推送、Tag 或 Release 发布。下载地址需等待对应 Release 附件公开后才能访问。

## 本地文件

```text
Package.swift
Artifacts/                         # 本地 XCFramework，不提交 Git
Sources/SobotClientSDKResources/
  include/SobotPackageResources.h
  SobotPackageResources.m
  Resources/SobotKit.bundle/
  Resources/PrivacyInfo.xcprivacy
```

三个本地 XCFramework 和资源暂取自已发布的 CocoaPods `4.7.3.1`，仅作为验证输入。SPM 首版编号为 `4.7.3`，正式发布源码基线仍需冻结；不会修改原 SDK 仓库的历史 Tag。

## 在 App 中验证

1. App 最低 iOS 版本为 15.0。使用独立 Demo，避免同时通过 Pods 或手动方式引入同名 SDK。
2. Release 公开后，在 Xcode 添加 `https://github.com/ZCSDK/SobotClientSDK-SPM.git`，使用 Exact Version `4.7.3-beta.1`，将 `SobotClientSDK` 产品加入 App Target。即使引用此本地目录，当前清单也会从远端下载二进制；验证远程安装时不要同时引入本地 Package。
3. 在主线程、首次使用 SDK 之前调用下面的资源准备方法；失败时停止初始化并检查错误。
4. 然后沿用原 SDK 初始化和客服业务代码。业务模块名仍为 `SobotKit`、`SobotChatClient`、`SobotCommon`。

Swift：

```swift
import SobotClientSDKResources
import SobotKit

// 放在主线程的 App 初始化流程中，早于任何 SDK 业务调用。
do {
    try SobotPackageResources.prepare()
    // 准备成功后执行原 SDK 初始化代码。
} catch {
    // 记录失败原因，本次不继续初始化 SDK。
    print("Sobot resource preparation failed: \(error)")
}
```

Objective-C：

```objective-c
@import SobotClientSDKResources;
#import <SobotKit/SobotKit.h>

// 放在主线程的 App 初始化方法中。
NSError *error = nil;
// 失败时退出当前初始化流程，不继续调用 SDK。
if (![SobotPackageResources prepareWithError:&error]) {
    NSLog(@"Sobot resource preparation failed: %@", error);
    return;
}
// 准备成功后执行原 SDK 初始化代码。
```

资源适配使用 SwiftPM 生成的 Objective-C Bundle 访问器，再通过 SDK 已有的 `spmModuleName` / `spmTargetName` 接口配置查找，最后验证 SDK 取到的确实是当前 Package 资源。未使用 KVC 修改私有缓存，也没有运行时方法替换。初始化过晚或存在旧的手动 SobotKit.bundle 时会明确报错；修正后重新启动 App。

## 本次验证（2026-11-13）

- `swift package dump-package`：通过，三个二进制 Target、资源 Target、iOS 15 最低版本和对外产品均可解析。
- iOS arm64 模拟器构建：通过。命令为 `swift build --triple arm64-apple-ios15.0-simulator --sdk <xcrun --sdk iphonesimulator --show-sdk-path 的输出>`。
- 构建仍提示现有 SobotCommon 头文件的 nullability 和 umbrella header 警告；本次未修改这些既有二进制头文件。
- 补充完成桌面 Objective-C / Swift 两个独立 Demo 的 App 编译与链接、模拟器安装启动、资源准备及图片/中文语言/区号 JSON 读取、SDK 初始化和客服页面打开。使用 Xcode 27.1、iPhone Duo / iOS 27.1，两个 App 均设置 `-ObjC`。
- Demo 路径：`/Users/lizh/Desktop/SobotSPMObjCDemo`、`/Users/lizh/Desktop/SobotSPMSwiftDemo`；各目录 README 和 Validation 保存验证记录与截图。SDK 内部 getVersion 返回 4.7.3，来源 CocoaPods 分发版本为 4.7.3.1。
- 用户补充确认两个 Demo 真机均能打开 SDK 并读取图片。后续 Release Archive 已成功，新增的隐私清单位于 `SobotClientSDK_SobotClientSDKResources.bundle/PrivacyInfo.xcprivacy`，仅一份且与 Pod 原件逐字节一致；Xcode 隐私报告生成与声明内容审查尚未完成。
- 上述运行验证使用此前的本地路径清单；当前远程配置已做清单解析和 ZIP/checksum 一致性检查，尚未完成远程下载验证。主动消息收发、全部语言/主题等完整业务验收仍需补充。

## 当前边界与发布前事项

- 本地二进制完整保留原样，没有修改原 SDK 源码或重新打包。
- 现有 SobotChatClient 产物内仍有嵌套 SobotCommon.framework；SDK 源码中仍有少量绕过统一入口的资源调用。资源准备成功不等于全部业务验收完成。
- 现有资源注册接口及缓存逻辑仍需后续正式适配；当前层使用已有公开接口完成本地验证。
- Swift/ObjC Demo 的基础调用与资源显示已通过；Framework 隐私清单和完整业务仍需正式验收。清单声明了系统 xml2，两个 Demo 宿主额外设置 `-ObjC` 以加载静态库 Category，需将该要求纳入正式接入说明。
- `Artifacts/` 不进入 Git。当前已切换为 `4.7.3-beta.1` 的 HTTPS ZIP URL 和真实 checksum，只有代码及对应 Release 附件均公开后，客户才能安装。
- XCFramework 替换后要同步资源，记录真实源码提交和构建信息，再完成统一验收。

参考：[SwiftPM Objective-C 资源访问器实现](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/ClangModuleBuildDescription.swift)。

## 每次发布需要修改什么

1. 制作本轮三个 ZIP，并计算各自的 `swift package compute-checksum`。
2. 更新 `Package.swift` 顶部的 `releaseVersion`，下载地址会同步使用新的 Tag。
3. 更新发生变化的 ZIP 对应的 checksum；即使架包内容相同，重新压缩也应重新计算。若直接复用字节完全相同的 ZIP，checksum 可以保持相同。
4. 如 SDK 配套资源、隐私声明或适配代码有变化，同步更新后再提交、推送和打新 Tag。
5. 对应 Release 上传本次计算过 checksum 的同一份 ZIP，再进行远程接入验证。

本轮附件已生成在 `/Users/lizh/Desktop/SobotSPM_4.7.3-beta.1_发布包`，其中 `checksums.json` 记录文件名与校验值。不要重新压缩后仍使用当前 checksum，也不要覆盖已有版本的 Tag 或附件。
