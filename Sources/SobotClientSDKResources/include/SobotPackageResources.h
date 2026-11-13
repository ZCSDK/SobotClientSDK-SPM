#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地资源准备失败时使用的错误域。
FOUNDATION_EXPORT NSErrorDomain const SobotPackageResourcesErrorDomain;

/// 资源准备错误；调用失败后不应继续初始化 SDK。
typedef NS_ENUM(NSInteger, SobotPackageResourcesErrorCode) {
    SobotPackageResourcesErrorNotMainThread = 1, // 初始化阶段统一在主线程调用。
    SobotPackageResourcesErrorMissingBundle = 2, // Package 资源未正确复制。
    SobotPackageResourcesErrorInvalidBundleName = 3, // 旧 SDK 名称接口不能表示生成的 Bundle。
    SobotPackageResourcesErrorUnexpectedBundle = 4 // SDK 缓存或旧手动资源覆盖了本次资源路径。
};

/// 将 SwiftPM 资源位置接入当前 SDK 的公开资源配置；须在任何 SDK 使用前调用。
@interface SobotPackageResources : NSObject

/// Package 内原样复制的 SobotKit.bundle；缺失时返回 nil，不回退到 App 资源。
@property(class, nonatomic, readonly, nullable) NSBundle *sdkBundle;

/// 在主线程准备并验证资源；Swift 侧使用 try SobotPackageResources.prepare()。
+ (BOOL)prepareWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(prepare());

@end

NS_ASSUME_NONNULL_END
