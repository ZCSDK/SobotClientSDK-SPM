#import "SobotPackageResources.h"
#import <SobotCommon/SobotCache.h>

// SwiftPM 为带资源的 Objective-C Target 生成此访问器；无需猜测其目录名称。
#ifndef SWIFTPM_MODULE_BUNDLE
#import "resource_bundle_accessor.h"
#endif

/// 公开错误域，供调用方记录或识别资源准备问题。
NSErrorDomain const SobotPackageResourcesErrorDomain = @"com.sobot.spm.resources";

/// 统一输出失败结果；不强制调用方提供 NSError 指针。
static BOOL SobotResourceFailure(NSError **error, SobotPackageResourcesErrorCode code, NSString *message) {
    // 调用方需要错误详情时再填充，避免解引用空指针。
    if (error != NULL) {
        *error = [NSError errorWithDomain:SobotPackageResourcesErrorDomain
                                    code:code
                                userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

@implementation SobotPackageResources

/// 用 SwiftPM 生成的外层 Bundle 定位内部 SDK 资源包。
+ (NSBundle *)sdkBundle {
    NSURL *url = [SWIFTPM_MODULE_BUNDLE URLForResource:@"SobotKit" withExtension:@"bundle"];
    // 未打包资源时明确返回 nil，禁止悄悄使用其他路径掩盖安装问题。
    if (url == nil) {
        return nil;
    }
    return [NSBundle bundleWithURL:url];
}

/// 复用现有 spmModuleName / spmTargetName 配置，并验证 SDK 确实选中了该 Bundle。
+ (BOOL)prepareWithError:(NSError **)error {
    // 清除调用方可能复用的旧错误值。
    if (error != NULL) {
        *error = nil;
    }
    // SDK 当前资源缓存不是并发注册接口，要求在主线程初始化前执行。
    if (![NSThread isMainThread]) {
        return SobotResourceFailure(error, SobotPackageResourcesErrorNotMainThread,
                                    @"Call SobotPackageResources.prepare on the main thread before SDK initialization.");
    }

    NSBundle *outerBundle = SWIFTPM_MODULE_BUNDLE;
    NSBundle *expectedBundle = self.sdkBundle;
    // 必须同时具备外层 Package Bundle 和原始 SDK Bundle。
    if (outerBundle == nil || expectedBundle == nil) {
        return SobotResourceFailure(error, SobotPackageResourcesErrorMissingBundle,
                                    @"SobotKit.bundle is missing from the Swift Package resources.");
    }

    NSString *generatedName = outerBundle.bundleURL.lastPathComponent.stringByDeletingPathExtension;
    NSRange separator = [generatedName rangeOfString:@"_"];
    // 旧 SDK 将两个配置值以 '_' 拼接；读取生成的真实名称后拆分，避免写死包名。
    if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) == generatedName.length) {
        return SobotResourceFailure(error, SobotPackageResourcesErrorInvalidBundleName,
                                    @"The generated resource bundle name is incompatible with the current SDK resource lookup.");
    }

    SobotCache *cache = [SobotCache shareSobotCache];
    NSString *previousModuleName = cache.spmModuleName;
    NSString *previousTargetName = cache.spmTargetName;
    cache.spmModuleName = [generatedName substringToIndex:separator.location];
    cache.spmTargetName = [generatedName substringFromIndex:NSMaxRange(separator)];

    NSBundle *resolvedBundle = [SobotCache getSourceBundle:nil withName:@"SobotKit"];
    NSString *expectedPath = expectedBundle.bundleURL.URLByResolvingSymlinksInPath.path;
    NSString *resolvedPath = resolvedBundle.bundleURL.URLByResolvingSymlinksInPath.path;
    // 检查实际查找结果，防止主 Bundle 遗留资源或提前初始化的缓存遮蔽 SPM 资源。
    if (![resolvedPath isEqualToString:expectedPath]) {
        cache.spmModuleName = previousModuleName;
        cache.spmTargetName = previousTargetName;
        return SobotResourceFailure(error, SobotPackageResourcesErrorUnexpectedBundle,
                                    @"SDK resolved a different resource bundle. Remove duplicate manual resources and call prepare before any SDK use in a fresh app run.");
    }
    return YES;
}

@end
