import SwiftUI
import MetalKit

struct MetalTextureViewColorWrapper: UIViewRepresentable {
    var rotationAngle: Double
    var capturedData: CameraCapturedData

    func makeUIView(context: Context) -> MetalTextureViewColor {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device is not available.")
        }
        let mtkView = MetalTextureViewColor(frame: .zero, device: metalDevice)
        return mtkView
    }

    func updateUIView(_ uiView: MetalTextureViewColor, context: Context) {
        guard let colorBuffer = capturedData.colorY else {
            print("No color buffer available.")
            return
        }
        uiView.updateColorTexture(pixelBuffer: colorBuffer)
    }
}

