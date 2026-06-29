#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WCMNNLoadCompletion)(BOOL success, NSString * _Nullable errorMessage);
typedef void (^WCMNNInferenceCompletion)(NSString * _Nullable output, NSString * _Nullable errorMessage);

@interface OnDeviceMNNBridge : NSObject

+ (BOOL)isRuntimeAvailable;

- (void)loadModelAtPath:(NSString *)modelPath completion:(WCMNNLoadCompletion)completion;

- (void)analyzeImage:(UIImage *)image
               prompt:(NSString *)prompt
            maxTokens:(NSInteger)maxTokens
           completion:(WCMNNInferenceCompletion)completion;

- (void)unloadModel;

@end

NS_ASSUME_NONNULL_END
