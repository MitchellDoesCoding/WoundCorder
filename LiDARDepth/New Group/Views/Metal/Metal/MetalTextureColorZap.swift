import MetalKit
import SwiftUI

struct MetalTextureColorZapView: UIViewRepresentable {
    var capturedData: CameraCapturedData

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update logic if necessary
    }

    func makeCoordinator() -> MTKColorZapCoordinator {
        MTKColorZapCoordinator(parent: self)
    }
}
