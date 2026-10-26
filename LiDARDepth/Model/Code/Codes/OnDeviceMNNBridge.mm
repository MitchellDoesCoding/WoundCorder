#import "OnDeviceMNNBridge.h"

#import <TargetConditionals.h>
#import <os/proc.h>

#include <algorithm>
#include <memory>
#include <exception>
#include <sstream>
#include <string>
#include <vector>

#if !TARGET_OS_SIMULATOR
#include <MNN/llm/llm.hpp>
#endif

@implementation OnDeviceMNNBridge {
    dispatch_queue_t _inferenceQueue;
#if !TARGET_OS_SIMULATOR
    std::shared_ptr<MNN::Transformer::Llm> _llm;
#endif
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _inferenceQueue = dispatch_queue_create("com.woundcorder.mnn-inference", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (BOOL)isRuntimeAvailable {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    return YES;
#endif
}

- (void)loadModelAtPath:(NSString *)modelPath completion:(WCMNNLoadCompletion)completion {
    dispatch_async(_inferenceQueue, ^{
#if TARGET_OS_SIMULATOR
        [self finishLoad:completion
                 success:NO
                   error:@"On-device Qwen inference requires a physical iPhone or iPad."];
#else
        @autoreleasepool {
            try {
            NSString *configPath = [modelPath stringByAppendingPathComponent:@"config.json"];
            BOOL isDirectory = NO;
            BOOL modelExists = [[NSFileManager defaultManager] fileExistsAtPath:modelPath isDirectory:&isDirectory];
            BOOL configExists = [[NSFileManager defaultManager] fileExistsAtPath:configPath];
            if (!modelExists || !isDirectory || !configExists) {
                [self finishLoad:completion
                         success:NO
                           error:@"The selected model folder is incomplete. config.json is required."];
                return;
            }

            self->_llm.reset();
            if (os_proc_available_memory() < 4500000000ULL) {
                [self finishLoad:completion success:NO error:@"There is not enough free memory right now. Close other apps or use Photo Check."];
                return;
            }
            std::string config = configPath.UTF8String;
            self->_llm.reset(MNN::Transformer::Llm::createLLM(config));
            if (!self->_llm) {
                [self finishLoad:completion success:NO error:@"MNN could not create the selected model."];
                return;
            }

            NSString *cacheRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"WoundCorder-MNN"];
            NSError *directoryError = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:cacheRoot
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&directoryError];
            if (directoryError) {
                self->_llm.reset();
                [self finishLoad:completion success:NO error:directoryError.localizedDescription];
                return;
            }

            NSString *runtimeJSON = [NSString stringWithFormat:
                @"{\"tmp_path\":\"%@\",\"use_mmap\":true,\"max_new_tokens\":512}",
                [self jsonEscapedString:cacheRoot]
            ];
            self->_llm->set_config(runtimeJSON.UTF8String);
            if (!self->_llm->load()) {
                self->_llm.reset();
                [self finishLoad:completion success:NO error:@"MNN could not load the selected model files."];
                return;
            }

            [self finishLoad:completion success:YES error:nil];
            } catch (const std::exception &exception) {
                self->_llm.reset();
                [self finishLoad:completion success:NO error:@"The model could not load. Use Photo Check or try again."];
            }
        }
#endif
    });
}

- (void)analyzeImage:(UIImage *)image
               prompt:(NSString *)prompt
            maxTokens:(NSInteger)maxTokens
           completion:(WCMNNInferenceCompletion)completion {
    dispatch_async(_inferenceQueue, ^{
#if TARGET_OS_SIMULATOR
        [self finishInference:completion
                       output:nil
                        error:@"On-device Qwen inference requires a physical iPhone or iPad."];
#else
        @autoreleasepool {
            try {
            if (!self->_llm) {
                [self finishInference:completion output:nil error:@"No on-device model is loaded."];
                return;
            }

            MNN::Express::VARP imageTensor = [self tensorForImage:image];
            if (!imageTensor.get()) {
                [self finishInference:completion output:nil error:@"The image could not be prepared for the model."];
                return;
            }

            MNN::Transformer::PromptImagePart imagePart;
            imagePart.image_data = imageTensor;
            imagePart.width = (int)CGImageGetWidth(image.CGImage);
            imagePart.height = (int)CGImageGetHeight(image.CGImage);

            MNN::Transformer::MultimodalPrompt multimodalPrompt;
            multimodalPrompt.prompt_template = std::string("<img>wound</img>\n") + prompt.UTF8String;
            multimodalPrompt.images["wound"] = imagePart;

            self->_llm->reset();
            std::ostringstream output;
            int tokenLimit = (int)std::clamp<NSInteger>(maxTokens, 64, 1024);
            self->_llm->response(multimodalPrompt, &output, "<eop>", tokenLimit);

            const auto *context = self->_llm->getContext();
            if (!context || context->status == MNN::Transformer::LlmStatus::INTERNAL_ERROR ||
                context->status == MNN::Transformer::LlmStatus::NOT_LOADED) {
                [self finishInference:completion output:nil error:@"The local model stopped before producing a result."];
                return;
            }

            NSString *result = [NSString stringWithUTF8String:output.str().c_str()];
            result = [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (result.length == 0) {
                [self finishInference:completion output:nil error:@"The local model returned an empty result."];
                return;
            }
            [self finishInference:completion output:result error:nil];
            } catch (const std::exception &exception) {
                [self finishInference:completion output:nil error:@"The model could not finish. Your Photo Check is still available."];
            }
        }
#endif
    });
}

- (void)unloadModel {
    dispatch_async(_inferenceQueue, ^{
#if !TARGET_OS_SIMULATOR
        self->_llm.reset();
#endif
    });
}

- (NSString *)jsonEscapedString:(NSString *)value {
    return [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

#if !TARGET_OS_SIMULATOR
- (MNN::Express::VARP)tensorForImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) {
        return MNN::Express::VARP();
    }

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) {
        return MNN::Express::VARP();
    }

    size_t bytesPerRow = width * 4;
    std::vector<uint8_t> pixels(height * bytesPerRow);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels.data(), width, height, 8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return MNN::Express::VARP();
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    auto tensor = MNN::Express::_Input(
        {(int)height, (int)width, 3},
        MNN::Express::NHWC,
        halide_type_of<uint8_t>()
    );
    uint8_t *destination = tensor->writeMap<uint8_t>();
    if (!destination) {
        return MNN::Express::VARP();
    }

    for (size_t pixel = 0; pixel < width * height; ++pixel) {
        size_t source = pixel * 4;
        size_t target = pixel * 3;
        // MNN vision preprocessing expects HWC BGR bytes and performs its own normalization.
        destination[target] = pixels[source + 2];
        destination[target + 1] = pixels[source + 1];
        destination[target + 2] = pixels[source];
    }
    return tensor;
}
#endif

- (void)finishLoad:(WCMNNLoadCompletion)completion success:(BOOL)success error:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, error);
    });
}

- (void)finishInference:(WCMNNInferenceCompletion)completion
                  output:(NSString *)output
                   error:(NSString *)error {
#if !TARGET_OS_SIMULATOR
    self->_llm.reset();
#endif
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(output, error);
    });
}

@end
