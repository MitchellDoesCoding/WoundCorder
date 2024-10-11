import SwiftUI
import MetalKit
import ARKit

final class MetalTextureViewColor: MTKView {
    private var textureCache: CVMetalTextureCache?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var metalDevice: MTLDevice!
    private var colorTexture: MTLTexture?

    init(frame: CGRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        self.metalDevice = device
        self.setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMetal() {
        guard let metalDevice = self.device else {
            fatalError("Metal device is not available.")
        }

        // Create the texture cache
        _ = CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache) // Suppressing the unused warning

        // Create a command queue
        self.commandQueue = metalDevice.makeCommandQueue()

        // Create a default pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        pipelineDescriptor.vertexFunction = metalDevice.makeDefaultLibrary()?.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = metalDevice.makeDefaultLibrary()?.makeFunction(name: "fragmentShader")
        pipelineDescriptor.vertexDescriptor = MTLVertexDescriptor()

        do {
            self.pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    func updateColorTexture(pixelBuffer: CVPixelBuffer) {
        guard let textureCache = self.textureCache else {
            fatalError("Texture cache is not initialized.")
        }

        // Create a Metal texture from the pixel buffer
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &texture)

        guard let unwrappedTexture = texture else {
            print("Failed to create texture from pixel buffer.")
            return
        }

        self.colorTexture = CVMetalTextureGetTexture(unwrappedTexture)
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = self.currentDrawable,
              let renderPassDescriptor = self.currentRenderPassDescriptor,
              let commandQueue = self.commandQueue,
              let pipelineState = self.pipelineState else {
            return
        }

        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        renderEncoder?.setRenderPipelineState(pipelineState)
        if let texture = self.colorTexture {
            renderEncoder?.setFragmentTexture(texture, index: 0)
        }

        renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder?.endEncoding()

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
