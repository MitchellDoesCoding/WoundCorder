import MetalKit
import SwiftUI

final class MTKPointCloudCoordinator: NSObject, MTKViewDelegate {
    var parent: MetalPointCloudView
    var textureCache: CVMetalTextureCache?

    init(parent: MetalPointCloudView) {
        self.parent = parent
    }

    func setupTextureCache(device: MTLDevice) {
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func draw(in view: MTKView) {
        guard let depthBuffer = parent.capturedData.depth else { return }
        guard let depthTexture = createTexture(from: depthBuffer, format: .r32Float) else { return }

        guard let commandQueue = view.device?.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let passDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        // Set the depth texture to the fragment shader
        renderEncoder.setFragmentTexture(depthTexture, index: 0)
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes for the MTKView
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer, format: MTLPixelFormat) -> MTLTexture? {
        var cvMetalTexture: CVMetalTexture?
        guard let textureCache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, format, width, height, 0, &cvMetalTexture)
        return cvMetalTexture != nil ? CVMetalTextureGetTexture(cvMetalTexture!) : nil
    }
}
