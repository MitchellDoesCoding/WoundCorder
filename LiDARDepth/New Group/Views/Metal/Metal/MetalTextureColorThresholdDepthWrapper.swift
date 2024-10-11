import SwiftUI
import MetalKit

struct MetalTextureColorThresholdDepthWrapper: UIViewRepresentable {
    var rotationAngle: Double
    @Binding var maxDepth: Float
    @Binding var minDepth: Float
    var capturedData: CameraCapturedData

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update MTKView as needed
    }

    func makeCoordinator() -> MTKColorThresholdDepthCoordinator {
        MTKColorThresholdDepthCoordinator(parent: self)
    }
}
