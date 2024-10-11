import MetalKit

final class MTKColorZapCoordinator: NSObject, MTKViewDelegate {
    var parent: MetalTextureColorZapView
    var textureCache: CVMetalTextureCache?

    init(parent: MetalTextureColorZapView) {
        self.parent = parent
        super.init()

        // Initialize Metal texture cache
        var newTextureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, MTLCreateSystemDefaultDevice()!, nil, &newTextureCache)
        self.textureCache = newTextureCache
    }

    func draw(in view: MTKView) {
        guard let depthBuffer = parent.capturedData.depth else {
            print("Depth buffer is missing.")
            return
        }

        guard let depthTexture = createTexture(from: depthBuffer, format: .r32Float) else {
            print("Failed to create depth texture.")
            return
        }

        guard let commandQueue = view.device?.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let passDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            print("Failed to set up Metal render pipeline.")
            return
        }

        renderEncoder.setFragmentTexture(depthTexture, index: 0)
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer, format: MTLPixelFormat) -> MTLTexture? {
        var cvMetalTexture: CVMetalTexture?
        guard let textureCache = textureCache else {
            print("Texture cache is unavailable.")
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, format, width, height, 0, &cvMetalTexture)
        return cvMetalTexture != nil ? CVMetalTextureGetTexture(cvMetalTexture!) : nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("Drawable size changed: \(size)")
    }
}
