import MetalKit
import Metal

final class MTKColorThresholdDepthCoordinator: NSObject, MTKViewDelegate {
    private var parent: MetalTextureColorThresholdDepthWrapper
    private var textureCache: CVMetalTextureCache?

    init(parent: MetalTextureColorThresholdDepthWrapper) {
        self.parent = parent
        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create Metal device.")
        }
        // Initialize the Metal texture cache
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    // MARK: - MTKViewDelegate Methods

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("Drawable size changed: \(size)")
    }

    func draw(in view: MTKView) {
        guard let depthBuffer = parent.capturedData.depth else {
            print("Depth buffer missing.")
            return
        }

        guard let depthTexture = createMetalTexture(from: depthBuffer, pixelFormat: .r32Float, planeIndex: 0) else {
            print("Failed to create depth texture.")
            return
        }

        guard let commandQueue = view.device?.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to create render encoder.")
            return
        }

        renderEncoder.setFragmentTexture(depthTexture, index: 0)
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }


    private func createMetalTexture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> MTLTexture? {
        var texture: CVMetalTexture?
        guard let cache = textureCache else {
            print("Texture cache is unavailable.")
            return nil
        }
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, pixelFormat,
                                                  CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex),
                                                  CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex),
                                                  planeIndex, &texture)
        return texture != nil ? CVMetalTextureGetTexture(texture!) : nil
    }
}
