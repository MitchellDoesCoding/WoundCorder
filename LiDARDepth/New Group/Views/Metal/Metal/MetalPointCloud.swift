import MetalKit
import Metal
import SwiftUI

struct MetalPointCloudView: UIViewRepresentable {
    var capturedData: CameraCapturedData

    func makeCoordinator() -> MTKPointCloudCoordinator {
        MTKPointCloudCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        context.coordinator.setupTextureCache(device: view.device!)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.parent = self
    }
}


