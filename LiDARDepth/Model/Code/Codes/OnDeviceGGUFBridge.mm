#import "OnDeviceGGUFBridge.h"
#import <TargetConditionals.h>
#include <memory>
#include <string>
#include <vector>
#include <stdexcept>
#if !TARGET_OS_SIMULATOR
#include <os/proc.h>
#include <llama/llama.h>
#include <llama/mtmd.h>
#include <llama/mtmd-helper.h>
#endif

@implementation OnDeviceGGUFBridge
+ (BOOL)isRuntimeAvailable {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    return YES;
#endif
}
- (void)analyzeImage:(UIImage *)image modelPath:(NSString *)modelPath visionPath:(NSString *)visionPath prompt:(NSString *)prompt completion:(void (^)(NSString *, NSString *))completion {
#if TARGET_OS_SIMULATOR
    completion(nil, @"Health context needs a supported physical device. Photo Check is available here.");
#else
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
    if (!jpeg) { completion(nil, @"The photo could not be prepared."); return; }
    // A process-wide serial queue bounds concurrent model allocations across screens.
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.woundcorder.gguf", DISPATCH_QUEUE_SERIAL);
        llama_backend_init();
    });
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSString *output = nil;
            NSString *failure = nil;
            try {
                if (os_proc_available_memory() < 4'500'000'000ULL) throw std::runtime_error("Not enough memory is free right now. Close other apps and try again, or use Photo Check.");
                auto mp = llama_model_default_params();
                mp.n_gpu_layers = 99;
                std::unique_ptr<llama_model, decltype(&llama_model_free)> model(llama_model_load_from_file(modelPath.UTF8String, mp), llama_model_free);
                if (!model) throw std::runtime_error("The downloaded model could not be opened.");
                auto cp = llama_context_default_params();
                cp.n_ctx = 4096;
                cp.n_batch = 512;
                cp.n_ubatch = 128;
                cp.n_threads = 4;
                cp.n_threads_batch = 4;
                std::unique_ptr<llama_context, decltype(&llama_free)> ctx(llama_init_from_model(model.get(), cp), llama_free);
                if (!ctx) throw std::runtime_error("Not enough working memory. Close other apps or use Photo Check.");
                auto vp = mtmd_context_params_default();
                vp.use_gpu = true;
                vp.n_threads = 4;
                vp.image_max_tokens = 1024;
                vp.warmup = false;
                std::unique_ptr<mtmd_context, decltype(&mtmd_free)> vision(mtmd_init_from_file(visionPath.UTF8String, model.get(), vp), mtmd_free);
                if (!vision || !mtmd_support_vision(vision.get())) throw std::runtime_error("The vision model could not be opened.");
                auto bitmapResult = mtmd_helper_bitmap_init_from_buf(vision.get(), (const unsigned char *)jpeg.bytes, jpeg.length, false, mtmd_helper_init_opt_default());
                std::unique_ptr<mtmd_bitmap, decltype(&mtmd_bitmap_free)> bitmap(bitmapResult.bitmap, mtmd_bitmap_free);
                if (!bitmap) throw std::runtime_error("The vision model could not read this photo.");
                // Pinned Qwen3.5 ChatML template, with thinking disabled for concise output.
                std::string text = "<|im_start|>system\nYou help document wound photos. Never diagnose or prescribe. Follow the requested JSON schema.<|im_end|>\n<|im_start|>user\n";
                text += mtmd_default_marker();
                text += "\n";
                text += prompt.UTF8String;
                text += "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
                mtmd_input_text input = {text.c_str(), text.size(), true, true};
                const mtmd_bitmap *bitmaps[] = {bitmap.get()};
                std::unique_ptr<mtmd_input_chunks, decltype(&mtmd_input_chunks_free)> chunks(mtmd_input_chunks_init(), mtmd_input_chunks_free);
                if (mtmd_tokenize(vision.get(), chunks.get(), &input, bitmaps, 1) != 0) throw std::runtime_error("The photo and health details could not be prepared.");
                if (mtmd_helper_get_n_tokens(chunks.get()) + 768 > cp.n_ctx) throw std::runtime_error("There is too much context for this model. Use fewer notes and try again.");
                llama_pos position = 0;
                if (mtmd_helper_eval_chunks(vision.get(), ctx.get(), chunks.get(), 0, 0, cp.n_batch, true, &position) != 0) throw std::runtime_error("Photo processing stopped. Try Photo Check.");
                std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(), llama_sampler_free);
                auto vocab = llama_model_get_vocab(model.get());
                std::string response;
                for (int i = 0; i < 768; ++i) {
                    llama_token token = llama_sampler_sample(sampler.get(), ctx.get(), -1);
                    if (llama_vocab_is_eog(vocab, token)) break;
                    std::vector<char> piece(256);
                    int count = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, false);
                    if (count < 0) { piece.resize(-count); count = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, false); }
                    if (count > 0) response.append(piece.data(), count);
                    auto batch = llama_batch_get_one(&token, 1);
                    if (llama_decode(ctx.get(), batch) != 0) throw std::runtime_error("The model stopped while preparing its comments.");
                }
                output = [[NSString alloc] initWithBytes:response.data() length:response.size() encoding:NSUTF8StringEncoding];
                if (!output.length) throw std::runtime_error("The model returned no comments.");
            } catch (const std::exception &error) {
                failure = [NSString stringWithUTF8String:error.what()];
            } catch (...) { failure = @"The local model could not finish. Try Photo Check."; }
            // All model allocations are released before notifying Swift.
            dispatch_async(dispatch_get_main_queue(), ^{ completion(output, failure); });
        }
    });
#endif
}
@end
