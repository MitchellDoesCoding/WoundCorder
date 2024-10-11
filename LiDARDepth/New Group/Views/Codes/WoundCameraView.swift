import SwiftUI
import AVFoundation

struct WoundCameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var maxDepthF: Double = 0.05
    @State private var minDepthF: Double = 0.0
    @State private var showPermissionsAlert = false
    @State private var showMeasurement = false
    

    var body: some View {
        ZStack {
            CameraPreview(manager: cameraManager)
                .ignoresSafeArea()
            DepthOverlay(
                manager: cameraManager,
                maxDepth: Binding(get: { Float(maxDepthF) }, set: { maxDepthF = Double($0) }),
                minDepth: Binding(get: { Float(minDepthF) }, set: { minDepthF = Double($0) })
            )
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Menu {
                        Section("Depth Range (m)") {
                            Slider(value: $minDepthF, in: 0.0...max(0.01, maxDepthF), step: 0.01) {
                                Text("Min")
                            }
                            Slider(value: $maxDepthF, in: minDepthF...2.0, step: 0.01) {
                                Text("Max")
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.large)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
                Spacer()
                HStack(spacing: 24) {
                    Button {
                        cameraManager.capturePhoto()
                    } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.2)).frame(width: 76, height: 76)
                            Circle().fill(Color.white).frame(width: 64, height: 64)
                        }
                    }

                    Button {
                        showMeasurement = true
                    } label: {
                        Text("Measure Wound")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear { requestPermissionsAndStart() }
        .onDisappear { cameraManager.stopStream() }
        .alert("Camera Access Needed", isPresented: $showPermissionsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enable camera permissions in Settings to use the wound camera.")
        }
        .sheet(isPresented: $showMeasurement) {
            ContentView()
        }
    }
    

    private func requestPermissionsAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraManager.startStream()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { cameraManager.startStream() } else { showPermissionsAlert = true }
                }
            }
        default:
            showPermissionsAlert = true
        }
    }
}

// Simple preview layer bridge for CameraManager's captureSession
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var manager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = manager.makePreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = context.coordinator.previewLayer else { return }
        layer.frame = uiView.bounds
        if layer.superlayer !== uiView.layer {
            uiView.layer.addSublayer(layer)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
