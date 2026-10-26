#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface OnDeviceGGUFBridge : NSObject
+ (BOOL)isRuntimeAvailable;
- (void)analyzeImage:(UIImage *)image
          modelPath:(NSString *)modelPath
         visionPath:(NSString *)visionPath
             prompt:(NSString *)prompt
         completion:(void (^)(NSString * _Nullable output, NSString * _Nullable errorMessage))completion;
@end
NS_ASSUME_NONNULL_END
