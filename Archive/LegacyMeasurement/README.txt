Historical measurement implementation, excluded from the app target.

The active workflow uses ARViewController and WoundGeometry. The old LiDARVolumeCalculator had no active callers; its unused instance and optional-module aliases have been removed. This source is retained for history, not execution. In particular, its visibility filter assumes a fixed world +Z camera direction and must not be reused as validated geometry. MeasurementTabView now opens history only; WoundCameraView routes through the current consent/intake flow. Global legacy scan controls cannot target the active scanner, whose commands and results are scoped to one capture session.

Unused CameraController, CameraManager, and DepthOverlay prototypes are also archived. Their automatic library saving and hard-coded camera settings are not part of the product. Photo capture is owned by ARCameraViewController (AVCaptureSession despite its compatibility name), and measurement by ARViewController (ARSession).
