import ARKit
import CoreImage
import CoreML
import Foundation
import UIKit
import Vision
import simd

enum TissueType: String, Codable {
    case granulation
    case slough
    case eschar
    case epithelializing
    case mixed
    case unknown
}

struct WoundColorFeatures {
    let meanLAB: (L: Float, a: Float, b: Float)
    let rednessIndex: Float
    let tissueClassification: TissueType
}

struct Wound3DGeometry {
    let boundaryWorldPoints: [SIMD3<Float>]
    let boundaryScreenPoints: [CGPoint]
    let deepestWorldPoint: SIMD3<Float>?
    let referenceSurfaceOrigin: SIMD3<Float>
    let referenceSurfaceNormal: SIMD3<Float>
    let sampledPointCount: Int
    let validDepthPixelCount: Int
}

struct WoundSegmentationResult {
    let mask: CVPixelBuffer
    let boundingRect: CGRect
    let areaCm2: Float
    let volumeCm3: Float
    let maxDepthMm: Float
    let perimeter: Float
    let confidence: Float
    let colorFeatures: WoundColorFeatures
    let geometry: Wound3DGeometry
}

final class WoundMultimodalSegmenter {
    private enum MaskSource {
        case coreML
        case heuristic
        case fused
    }

    private struct ColorGrid {
        let width: Int
        let height: Int
        var rLinear: [Float]
        var gLinear: [Float]
        var bLinear: [Float]
        var lStar: [Float]
        var aStar: [Float]
        var bStar: [Float]
        var rednessIndex: [Float]
    }

    private struct DepthGrid {
        let width: Int
        let height: Int
        var depthM: [Float]
        var hasDepth: [Bool]
        var highConfidence: [Bool]
        var normalMagnitude: [Float]
        let depthCoverage: Float
        let confidenceMean: Float
        let medianDepthM: Float
    }

    private struct SkinReference {
        let l: Float
        let a: Float
        let b: Float
        let redness: Float
        let lScale: Float
        let aScale: Float
        let bScale: Float
    }

    private struct DepthSurfaceReference {
        let xSlope: Float
        let ySlope: Float
        let intercept: Float
        let noiseM: Float

        func depth(atX x: Float, y: Float) -> Float {
            xSlope * x + ySlope * y + intercept
        }
    }

    private struct MaskGrid {
        let width: Int
        let height: Int
        var values: [UInt8]

        func foregroundRatio(threshold: UInt8) -> Float {
            guard !values.isEmpty else { return 0 }
            let count = values.reduce(0) { $0 + ($1 > threshold ? 1 : 0) }
            return Float(count) / Float(values.count)
        }

        var meanProbability: Float {
            guard !values.isEmpty else { return 0 }
            let sum = values.reduce(0) { $0 + Int($1) }
            return Float(sum) / Float(values.count * 255)
        }
    }

    private struct Plane {
        let origin: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    private struct MetricResult {
        let areaCm2: Float
        let volumeCm3: Float
        let maxDepthMm: Float
        let perimeterCm: Float
        let deepestWorldPoint: SIMD3<Float>?
        let plane: Plane
        let sampledPointCount: Int
        let validDepthPixelCount: Int
        let depthCoverage: Float
        let planeSupport: Float
    }

    private let model: MLModel?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let targetWidth = 256
    private let targetHeight = 256
    private let segmentationThreshold: UInt8 = 82
    private var previousMask: MaskGrid?
    private var previousCameraTransform: simd_float4x4?

    private let channelMeans: [Float] = [0.485, 0.456, 0.406, 0.50, 0.50, 0.50, 0.00, 0.12]
    private let channelStds: [Float] = [0.229, 0.224, 0.225, 0.22, 0.20, 0.20, 0.08, 0.18]

    init(modelName: String = "WoundSegmentation") {
        let loadedModel: MLModel?
        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            loadedModel = try? MLModel(contentsOf: compiledURL)
        } else if let sourceURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodel"),
                  let compiledURL = try? MLModel.compileModel(at: sourceURL) {
            loadedModel = try? MLModel(contentsOf: compiledURL)
        } else {
            loadedModel = nil
        }

        let description = loadedModel?.modelDescription.metadata[MLModelMetadataKey.description]
            as? String
        let isPlaceholder = description?.localizedCaseInsensitiveContains("placeholder") == true
            && description?.localizedCaseInsensitiveContains("zero") == true
        // The bundled development asset intentionally emits an all-zero mask. Do
        // not spend scan time running it or report that output as learned evidence.
        model = isPlaceholder ? nil : loadedModel
    }

    func resetTemporalState() {
        previousMask = nil
        previousCameraTransform = nil
    }

    func segment(
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation,
        preferredCameraROI: CGRect? = nil
    ) -> WoundSegmentationResult? {
        guard viewportSize.width > 2, viewportSize.height > 2 else { return nil }
        // Use same-frame LiDAR geometry with the RGB image. ARKit's temporally
        // smoothed map can lag the wound edge while the device is moving.
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }
        guard let colorGrid = makeColorGrid(from: frame.capturedImage, width: targetWidth, height: targetHeight) else { return nil }
        guard let depthGrid = makeDepthGrid(
            from: depthData.depthMap,
            confidenceMap: depthData.confidenceMap,
            width: targetWidth,
            height: targetHeight
        ) else { return nil }

        let modelMask = runCoreMLMask(
            rgbPixelBuffer: frame.capturedImage,
            colorGrid: colorGrid,
            depthGrid: depthGrid
        )
        let lockedROI: CGRect? = {
            guard let preferredCameraROI else { return nil }
            let clipped = preferredCameraROI.standardized.intersection(
                CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            guard !clipped.isNull, clipped.width > 0.002, clipped.height > 0.002 else { return nil }
            return clipped
        }()
        let heuristicMask = makeHeuristicMask(
            colorGrid: colorGrid,
            depthGrid: depthGrid,
            requiredNormalizedROI: lockedROI
        )

        let maskSource: MaskSource
        let fusedMask: MaskGrid
        if let modelMask,
           modelMask.foregroundRatio(threshold: segmentationThreshold) >= 0.0005,
           modelMask.foregroundRatio(threshold: segmentationThreshold) <= 0.48 {
            let fusedCandidate = keepBestComponent(
                combine(modelMask: modelMask, heuristicMask: heuristicMask),
                preferredCenterBias: 0.14,
                requiredNormalizedROI: lockedROI
            )
            let fusedRatio = fusedCandidate.foregroundRatio(threshold: segmentationThreshold)
            if fusedRatio >= 0.0004, fusedRatio <= 0.48 {
                fusedMask = fusedCandidate
                maskSource = .fused
            } else {
                fusedMask = keepBestComponent(
                    heuristicMask,
                    preferredCenterBias: 0.20,
                    requiredNormalizedROI: lockedROI
                )
                maskSource = .heuristic
            }
        } else {
            fusedMask = keepBestComponent(
                heuristicMask,
                preferredCenterBias: 0.20,
                requiredNormalizedROI: lockedROI
            )
            maskSource = .heuristic
        }

        // Raw image-space masks should only be blended when the camera pose is
        // nearly unchanged. During a LiDAR sweep the world-space controller lock
        // supplies stability; blending an unwarped old image creates edge lag.
        let temporalMask = cameraMotionAllowsTemporalSmoothing(frame.camera.transform)
            ? applyTemporalSmoothing(to: fusedMask, requiredNormalizedROI: lockedROI)
            : fusedMask

        let temporalForegroundRatio = temporalMask.foregroundRatio(threshold: segmentationThreshold)
        guard temporalForegroundRatio >= 0.0004, temporalForegroundRatio <= 0.55 else { return nil }
        guard let maskBuffer = makeMaskPixelBuffer(
            from: temporalMask,
            binaryThreshold: segmentationThreshold
        ) else { return nil }

        let normalizedBoundary = boundaryPolygon(
            from: temporalMask,
            pixelBuffer: maskBuffer,
            threshold: segmentationThreshold
        )
        guard normalizedBoundary.count >= 3 else { return nil }

        let screenBoundary = normalizedBoundary.compactMap {
            screenPoint(fromCameraNormalized: $0, frame: frame, viewportSize: viewportSize, orientation: orientation)
        }
        guard screenBoundary.count >= 3 else { return nil }

        guard let worldBoundary = completeWorldBoundary(
            fromCameraNormalized: normalizedBoundary,
            depthGrid: depthGrid,
            frame: frame
        ) else { return nil }

        let metrics = compute3DMetrics(
            mask: temporalMask,
            depthGrid: depthGrid,
            frame: frame,
            boundaryWorldPoints: worldBoundary
        )
        guard let metrics else { return nil }

        let boundingRect = boundingRectForMask(temporalMask, threshold: segmentationThreshold)
        let colorFeatures = computeColorFeatures(mask: temporalMask, colorGrid: colorGrid)
        let confidence = computeConfidence(
            mask: temporalMask,
            source: maskSource,
            metrics: metrics,
            depthGrid: depthGrid
        )

        let geometry = Wound3DGeometry(
            boundaryWorldPoints: worldBoundary,
            boundaryScreenPoints: screenBoundary,
            deepestWorldPoint: metrics.deepestWorldPoint,
            referenceSurfaceOrigin: metrics.plane.origin,
            referenceSurfaceNormal: metrics.plane.normal,
            sampledPointCount: metrics.sampledPointCount,
            validDepthPixelCount: metrics.validDepthPixelCount
        )

        // Invalid partial results must not become the next temporal reference.
        previousMask = temporalMask
        previousCameraTransform = frame.camera.transform

        return WoundSegmentationResult(
            mask: maskBuffer,
            boundingRect: boundingRect,
            areaCm2: metrics.areaCm2,
            volumeCm3: metrics.volumeCm3,
            maxDepthMm: metrics.maxDepthMm,
            perimeter: metrics.perimeterCm,
            confidence: confidence,
            colorFeatures: colorFeatures,
            geometry: geometry
        )
    }

    private func runCoreMLMask(
        rgbPixelBuffer: CVPixelBuffer,
        colorGrid: ColorGrid,
        depthGrid: DepthGrid
    ) -> MaskGrid? {
        guard let model else { return nil }
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first,
              let inputDescription = model.modelDescription.inputDescriptionsByName[inputName] else {
            return nil
        }

        let featureValue: MLFeatureValue?
        switch inputDescription.type {
        case .multiArray:
            guard let fused = makeFusedInputTensor(colorGrid: colorGrid, depthGrid: depthGrid) else { return nil }
            featureValue = MLFeatureValue(multiArray: fused)
        case .image:
            let width = inputDescription.imageConstraint?.pixelsWide ?? targetWidth
            let height = inputDescription.imageConstraint?.pixelsHigh ?? targetHeight
            guard let inputImage = makeModelImageBuffer(from: rgbPixelBuffer, width: width, height: height) else { return nil }
            featureValue = MLFeatureValue(pixelBuffer: inputImage)
        default:
            return nil
        }

        guard let featureValue,
              let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: featureValue]),
              let output = try? model.prediction(from: provider) else {
            return nil
        }

        for outputName in model.modelDescription.outputDescriptionsByName.keys {
            guard let value = output.featureValue(for: outputName) else { continue }
            if value.type == .image, let buffer = value.imageBufferValue {
                return maskGrid(from: buffer, width: targetWidth, height: targetHeight)
            }
            if value.type == .multiArray, let array = value.multiArrayValue {
                return maskGrid(from: array, width: targetWidth, height: targetHeight)
            }
        }

        return nil
    }

    private func makeFusedInputTensor(colorGrid: ColorGrid, depthGrid: DepthGrid) -> MLMultiArray? {
        guard colorGrid.width == depthGrid.width, colorGrid.height == depthGrid.height else { return nil }
        let width = colorGrid.width
        let height = colorGrid.height
        let channelSize = width * height
        guard let array = try? MLMultiArray(
            shape: [1, 8, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else {
            return nil
        }

        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: 8 * channelSize)
        func write(_ value: Float, channel: Int, index: Int) {
            let mean = channelMeans[channel]
            let std = max(channelStds[channel], 0.0001)
            pointer[channel * channelSize + index] = (value - mean) / std
        }

        for index in 0..<channelSize {
            write(colorGrid.rLinear[index], channel: 0, index: index)
            write(colorGrid.gLinear[index], channel: 1, index: index)
            write(colorGrid.bLinear[index], channel: 2, index: index)
            write(colorGrid.lStar[index] / 100.0, channel: 3, index: index)
            write((colorGrid.aStar[index] + 128.0) / 255.0, channel: 4, index: index)
            write((colorGrid.bStar[index] + 128.0) / 255.0, channel: 5, index: index)
            let depthNormalized = depthGrid.hasDepth[index] ? depthGrid.depthM[index] - depthGrid.medianDepthM : 0
            write(clamp(depthNormalized, -0.18, 0.18), channel: 6, index: index)
            write(depthGrid.normalMagnitude[index], channel: 7, index: index)
        }

        return array
    }

    private func makeModelImageBuffer(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        var output: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        image = image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / max(1, extent.width),
                y: CGFloat(height) / max(1, extent.height)
            ))
        ciContext.render(
            image,
            to: output,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    private func makeColorGrid(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> ColorGrid? {
        guard let bytes = rgbaBytes(from: pixelBuffer, width: width, height: height) else { return nil }
        let count = width * height
        var rLinear = [Float](repeating: 0, count: count)
        var gLinear = [Float](repeating: 0, count: count)
        var bLinear = [Float](repeating: 0, count: count)
        var lStar = [Float](repeating: 0, count: count)
        var aStar = [Float](repeating: 0, count: count)
        var bStar = [Float](repeating: 0, count: count)
        var rednessIndex = [Float](repeating: 0, count: count)

        for index in 0..<count {
            let byteIndex = index * 4
            let rSRGB = Float(bytes[byteIndex]) / 255.0
            let gSRGB = Float(bytes[byteIndex + 1]) / 255.0
            let bSRGB = Float(bytes[byteIndex + 2]) / 255.0
            let r = srgbToLinear(rSRGB)
            let g = srgbToLinear(gSRGB)
            let b = srgbToLinear(bSRGB)
            let lab = rgbToLAB(r: r, g: g, b: b)

            rLinear[index] = r
            gLinear[index] = g
            bLinear[index] = b
            lStar[index] = lab.L
            aStar[index] = lab.a
            bStar[index] = lab.b
            rednessIndex[index] = (r - b) / max(r + b, 0.0001)
        }

        return ColorGrid(
            width: width,
            height: height,
            rLinear: rLinear,
            gLinear: gLinear,
            bLinear: bLinear,
            lStar: lStar,
            aStar: aStar,
            bStar: bStar,
            rednessIndex: rednessIndex
        )
    }

    private func rgbaBytes(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [UInt8]? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        image = image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / max(1, extent.width),
                y: CGFloat(height) / max(1, extent.height)
            ))

        guard let cgImage = ciContext.createCGImage(
            image,
            from: CGRect(x: 0, y: 0, width: width, height: height)
        ) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drew ? bytes : nil
    }

    private func makeDepthGrid(
        from depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        width: Int,
        height: Int
    ) -> DepthGrid? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0 else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceBytesPerRow = 0
        var confidenceMax: UInt8 = 0
        if let confidenceMap,
           CVPixelBufferGetWidth(confidenceMap) == depthWidth,
           CVPixelBufferGetHeight(confidenceMap) == depthHeight {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
            if let confidenceBase {
                for y in stride(from: 0, to: depthHeight, by: max(1, depthHeight / 24)) {
                    let row = confidenceBase.advanced(by: y * confidenceBytesPerRow)
                    for x in stride(from: 0, to: depthWidth, by: max(1, depthWidth / 24)) {
                        confidenceMax = max(confidenceMax, row.load(fromByteOffset: x, as: UInt8.self))
                    }
                }
            }
        }
        defer {
            if let confidenceMap, confidenceBase != nil {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        let count = width * height
        var depthValues = [Float](repeating: 0, count: count)
        var hasDepth = [Bool](repeating: false, count: count)
        var highConfidence = [Bool](repeating: false, count: count)
        var validDepths: [Float] = []
        validDepths.reserveCapacity(count)
        var confidenceSum: Float = 0

        for y in 0..<height {
            let sourceY = min(depthHeight - 1, max(0, Int((Float(y) + 0.5) / Float(height) * Float(depthHeight))))
            let depthRow = depthBase.advanced(by: sourceY * CVPixelBufferGetBytesPerRow(depthMap))

            for x in 0..<width {
                let sourceX = min(depthWidth - 1, max(0, Int((Float(x) + 0.5) / Float(width) * Float(depthWidth))))
                let index = y * width + x
                let depthM = depthRow.load(fromByteOffset: sourceX * MemoryLayout<Float>.size, as: Float.self)

                var confidenceValue: UInt8 = confidenceMax > 0 ? confidenceMax : 255
                if let confidenceBase {
                    let confidenceRow = confidenceBase.advanced(by: sourceY * confidenceBytesPerRow)
                    confidenceValue = confidenceRow.load(fromByteOffset: sourceX, as: UInt8.self)
                }

                let isHigh = isDepthConfidenceUsable(confidenceValue, maximumSeen: confidenceMax)
                confidenceSum += normalizedConfidence(confidenceValue, maximumSeen: confidenceMax)

                if depthM.isFinite, depthM > 0.02, depthM < 5.0, isHigh {
                    depthValues[index] = depthM
                    hasDepth[index] = true
                    highConfidence[index] = true
                    validDepths.append(depthM)
                } else if depthM.isFinite, depthM > 0.02, depthM < 5.0 {
                    depthValues[index] = depthM
                    hasDepth[index] = true
                    highConfidence[index] = false
                    validDepths.append(depthM)
                }
            }
        }

        guard !validDepths.isEmpty else { return nil }

        depthValues = fillDepthHoles(depthValues, valid: hasDepth, width: width, height: height)
        let medianDepth = percentile(validDepths.sorted(), 0.50)
        let normalMagnitude = computeNormalMagnitude(depth: depthValues, width: width, height: height)
        let coverage = Float(hasDepth.filter { $0 }.count) / Float(max(1, count))
        let confidenceMean = confidenceSum / Float(max(1, count))

        return DepthGrid(
            width: width,
            height: height,
            depthM: depthValues,
            hasDepth: hasDepth,
            highConfidence: highConfidence,
            normalMagnitude: normalMagnitude,
            depthCoverage: coverage,
            confidenceMean: confidenceMean,
            medianDepthM: medianDepth
        )
    }

    private func fillDepthHoles(_ depth: [Float], valid: [Bool], width: Int, height: Int) -> [Float] {
        var output = depth
        var validState = valid
        for _ in 0..<2 {
            var next = output
            var nextValid = validState
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    if validState[index] { continue }
                    var sum: Float = 0
                    var count: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx
                            let ny = y + dy
                            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                            let neighborIndex = ny * width + nx
                            guard validState[neighborIndex] else { continue }
                            sum += output[neighborIndex]
                            count += 1
                        }
                    }
                    if count >= 3 {
                        next[index] = sum / count
                        nextValid[index] = true
                    }
                }
            }
            output = next
            validState = nextValid
        }
        return output
    }

    private func computeNormalMagnitude(depth: [Float], width: Int, height: Int) -> [Float] {
        var normal = [Float](repeating: 0, count: width * height)
        guard width > 2, height > 2 else { return normal }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let left = depth[y * width + x - 1]
                let right = depth[y * width + x + 1]
                let up = depth[(y - 1) * width + x]
                let down = depth[(y + 1) * width + x]
                let dx = right - left
                let dy = down - up
                normal[y * width + x] = clamp(hypot(dx, dy) / 0.024, 0, 1)
            }
        }
        return normal
    }

    private func periwoundReferenceIndices(
        width: Int,
        height: Int,
        requiredNormalizedROI: CGRect?
    ) -> [Int] {
        let outer: CGRect
        let inner: CGRect
        if let requiredNormalizedROI {
            outer = requiredNormalizedROI.standardized.intersection(
                CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            inner = outer.insetBy(
                dx: outer.width * 0.19,
                dy: outer.height * 0.19
            )
        } else {
            // Acquisition guidance keeps the wound centered. This band is close
            // enough to represent the same limb while excluding the likely wound.
            outer = CGRect(x: 0.16, y: 0.16, width: 0.68, height: 0.68)
            inner = CGRect(x: 0.34, y: 0.34, width: 0.32, height: 0.32)
        }

        guard !outer.isNull, outer.width > 0.01, outer.height > 0.01 else { return [] }
        var indices: [Int] = []
        indices.reserveCapacity(max(32, width * height / 8))
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                )
                if outer.contains(point), !inner.contains(point) {
                    indices.append(y * width + x)
                }
            }
        }
        return indices
    }

    private func makeSkinReference(
        colorGrid: ColorGrid,
        indices: [Int]
    ) -> SkinReference? {
        let usable = indices.filter { colorGrid.lStar.indices.contains($0) }
        guard usable.count >= 24 else { return nil }

        let lValues = usable.map { colorGrid.lStar[$0] }.sorted()
        let aValues = usable.map { colorGrid.aStar[$0] }.sorted()
        let bValues = usable.map { colorGrid.bStar[$0] }.sorted()
        let rednessValues = usable.map { colorGrid.rednessIndex[$0] }.sorted()
        let l = percentile(lValues, 0.50)
        let a = percentile(aValues, 0.50)
        let b = percentile(bValues, 0.50)
        let redness = percentile(rednessValues, 0.50)

        let lMAD = percentile(lValues.map { abs($0 - l) }.sorted(), 0.50)
        let aMAD = percentile(aValues.map { abs($0 - a) }.sorted(), 0.50)
        let bMAD = percentile(bValues.map { abs($0 - b) }.sorted(), 0.50)
        return SkinReference(
            l: l,
            a: a,
            b: b,
            redness: redness,
            lScale: max(5.0, lMAD * 2.8),
            aScale: max(3.5, aMAD * 2.8),
            bScale: max(4.0, bMAD * 2.8)
        )
    }

    private func makeDepthSurfaceReference(
        depthGrid: DepthGrid,
        indices: [Int]
    ) -> DepthSurfaceReference? {
        let preferred = indices.filter {
            depthGrid.depthM.indices.contains($0)
                && depthGrid.hasDepth[$0]
                && depthGrid.highConfidence[$0]
        }
        // Weak LiDAR confidence disables geometric support; it never falls back
        // to noisy depth that could create a wound-shaped false positive.
        let usable = preferred
        guard usable.count >= 24 else { return nil }

        func fit(_ sampleIndices: [Int]) -> SIMD3<Float>? {
            var sxx: Float = 0
            var sxy: Float = 0
            var sx: Float = 0
            var syy: Float = 0
            var sy: Float = 0
            var sxz: Float = 0
            var syz: Float = 0
            var sz: Float = 0
            for index in sampleIndices {
                let x = (Float(index % depthGrid.width) + 0.5) / Float(depthGrid.width) - 0.5
                let y = (Float(index / depthGrid.width) + 0.5) / Float(depthGrid.height) - 0.5
                let z = depthGrid.depthM[index]
                sxx += x * x
                sxy += x * y
                sx += x
                syy += y * y
                sy += y
                sxz += x * z
                syz += y * z
                sz += z
            }
            let count = Float(sampleIndices.count)
            return solve3x3(
                (
                    SIMD3<Float>(sxx, sxy, sx),
                    SIMD3<Float>(sxy, syy, sy),
                    SIMD3<Float>(sx, sy, count)
                ),
                rhs: SIMD3<Float>(sxz, syz, sz)
            )
        }

        guard let initial = fit(usable) else { return nil }
        let residuals = usable.map { index -> Float in
            let x = (Float(index % depthGrid.width) + 0.5) / Float(depthGrid.width) - 0.5
            let y = (Float(index / depthGrid.width) + 0.5) / Float(depthGrid.height) - 0.5
            return depthGrid.depthM[index] - (initial.x * x + initial.y * y + initial.z)
        }
        let medianResidual = percentile(residuals.sorted(), 0.50)
        let mad = percentile(residuals.map { abs($0 - medianResidual) }.sorted(), 0.50)
        let tolerance = max(0.0025, mad * 3.5)
        let inliers = zip(usable, residuals).compactMap { index, residual in
            abs(residual - medianResidual) <= tolerance ? index : nil
        }
        let refined = inliers.count >= max(18, usable.count / 2) ? (fit(inliers) ?? initial) : initial
        return DepthSurfaceReference(
            xSlope: refined.x,
            ySlope: refined.y,
            intercept: refined.z,
            noiseM: max(0.0012, mad * 1.8)
        )
    }

    private func makeHeuristicMask(
        colorGrid: ColorGrid,
        depthGrid: DepthGrid,
        requiredNormalizedROI: CGRect?
    ) -> MaskGrid {
        let width = colorGrid.width
        let height = colorGrid.height
        let count = width * height

        let localL = boxMean(colorGrid.lStar, width: width, height: height, radius: 14)
        let localA = boxMean(colorGrid.aStar, width: width, height: height, radius: 14)
        let localB = boxMean(colorGrid.bStar, width: width, height: height, radius: 14)
        let localDepth = boxMean(
            depthGrid.depthM,
            valid: depthGrid.hasDepth,
            width: width,
            height: height,
            radius: 12,
            fallback: depthGrid.medianDepthM
        )
        let referenceIndices = periwoundReferenceIndices(
            width: width,
            height: height,
            requiredNormalizedROI: requiredNormalizedROI
        )
        let skinReference = makeSkinReference(colorGrid: colorGrid, indices: referenceIndices)
        let depthSurface = makeDepthSurfaceReference(depthGrid: depthGrid, indices: referenceIndices)

        var scores = [Float](repeating: 0, count: count)
        scores.reserveCapacity(count)
        let preferredCenterX = Float(requiredNormalizedROI?.midX ?? 0.5)
        let preferredCenterY = Float(requiredNormalizedROI?.midY ?? 0.5)
        let preferredCenterScale: Float = {
            guard let requiredNormalizedROI else { return 0.78 }
            return max(
                0.08,
                hypot(Float(requiredNormalizedROI.width), Float(requiredNormalizedROI.height)) * 0.75
            )
        }()

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let nx = (Float(x) + 0.5) / Float(width)
                let ny = (Float(y) + 0.5) / Float(height)
                if let requiredNormalizedROI,
                   !requiredNormalizedROI.contains(CGPoint(x: CGFloat(nx), y: CGFloat(ny))) {
                    scores[index] = 0
                    continue
                }
                let deltaL = colorGrid.lStar[index] - localL[index]
                let deltaA = colorGrid.aStar[index] - localA[index]
                let deltaB = colorGrid.bStar[index] - localB[index]
                let colorDistance = sqrt(deltaL * deltaL + deltaA * deltaA + deltaB * deltaB)
                let localContrast = clamp(colorDistance / 42.0, 0, 1)

                let referenceL = skinReference?.l ?? localL[index]
                let referenceA = skinReference?.a ?? localA[index]
                let referenceB = skinReference?.b ?? localB[index]
                let skinDeltaL = colorGrid.lStar[index] - referenceL
                let skinDeltaA = colorGrid.aStar[index] - referenceA
                let skinDeltaB = colorGrid.bStar[index] - referenceB
                let normalizedSkinDistance = sqrt(
                    pow(skinDeltaL / (skinReference?.lScale ?? 9.0), 2)
                        + pow(skinDeltaA / (skinReference?.aScale ?? 7.0), 2)
                        + pow(skinDeltaB / (skinReference?.bScale ?? 8.0), 2)
                )
                let skinContrast = clamp(normalizedSkinDistance / 2.35, 0, 1)

                let relativeRedness = clamp((skinDeltaA - 1.5) / 18.0, 0, 1)
                let absoluteRedness = clamp(
                    (colorGrid.rednessIndex[index] - (skinReference?.redness ?? 0) - 0.015) / 0.20,
                    0,
                    1
                )
                let redness = max(relativeRedness, absoluteRedness * max(localContrast, skinContrast))
                let yellowSlough = clamp((skinDeltaB - 3.0) / 24.0, 0, 1)
                let darkEschar = clamp((-skinDeltaL - 4.0) / 28.0, 0, 1)
                let tissueCue = max(redness, max(yellowSlough, darkEschar))

                let surfaceDepth = depthSurface?.depth(atX: nx - 0.5, y: ny - 0.5)
                    ?? localDepth[index]
                let depthResidual = depthGrid.depthM[index] - surfaceDepth
                let depthNoise = depthSurface?.noiseM ?? 0.0025
                let depressionCue = clamp((depthResidual - depthNoise) / 0.022, 0, 1)
                let depthCue = depthGrid.highConfidence[index]
                    ? max(depressionCue, depthGrid.normalMagnitude[index] * 0.20)
                    : 0

                let centerDistance = hypot(nx - preferredCenterX, ny - preferredCenterY)
                let centerWeight = clamp(1.0 - centerDistance / preferredCenterScale, 0, 1)

                let borderPenalty: Float = (nx < 0.025 || nx > 0.975 || ny < 0.025 || ny > 0.975) ? 0.18 : 0
                let colorCue = max(tissueCue, 0.70 * skinContrast + 0.30 * localContrast)
                let colorSupport = clamp((colorCue - 0.08) / 0.52, 0, 1)
                let supportedDepth = depthCue * colorSupport
                let agreement = sqrt(max(0, colorCue * depthCue))
                var score = 0.58 * colorCue
                    + 0.18 * localContrast
                    + 0.13 * supportedDepth
                    + 0.07 * agreement
                    + 0.04 * centerWeight
                    - borderPenalty
                if !depthGrid.hasDepth[index] {
                    score *= 0.82
                }
                scores[index] = clamp(score, 0, 1)
            }
        }

        let thresholdScores: [Float] = {
            guard let requiredNormalizedROI else { return scores }
            return scores.enumerated().compactMap { index, score in
                let x = index % width
                let y = index / width
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                )
                return requiredNormalizedROI.contains(point) ? score : nil
            }
        }()
        guard !thresholdScores.isEmpty else {
            return MaskGrid(width: width, height: height, values: [UInt8](repeating: 0, count: count))
        }
        let sortedScores = thresholdScores.sorted()
        let isLockedROI = requiredNormalizedROI != nil
        let highThreshold = max(
            isLockedROI ? 0.28 : 0.34,
            percentile(sortedScores, isLockedROI ? 0.82 : 0.90)
        )
        let lowThreshold = max(
            isLockedROI ? 0.16 : 0.20,
            min(
                highThreshold * (isLockedROI ? 0.68 : 0.74),
                percentile(sortedScores, isLockedROI ? 0.55 : 0.70)
            )
        )

        // Start from pixels with strong evidence, then retain their weaker but connected
        // edge pixels. A single high threshold consistently clips low-contrast wound rims.
        var mask = hysteresisMask(
            scores: scores,
            width: width,
            height: height,
            highThreshold: highThreshold,
            lowThreshold: lowThreshold
        )
        mask = morphologyClose(mask, width: width, height: height, threshold: segmentationThreshold)
        mask = fillEnclosedHoles(mask, width: width, height: height, threshold: segmentationThreshold)
        return keepBestComponent(
            MaskGrid(width: width, height: height, values: mask),
            preferredCenterBias: 0.20,
            requiredNormalizedROI: requiredNormalizedROI
        )
    }

    private func hysteresisMask(
        scores: [Float],
        width: Int,
        height: Int,
        highThreshold: Float,
        lowThreshold: Float
    ) -> [UInt8] {
        guard width > 0, height > 0, scores.count == width * height else { return [] }

        var selected = [Bool](repeating: false, count: scores.count)
        var queue: [Int] = []
        queue.reserveCapacity(scores.count / 8)

        for index in scores.indices where scores[index] >= highThreshold {
            selected[index] = true
            queue.append(index)
        }

        var queueIndex = 0
        while queueIndex < queue.count {
            let index = queue[queueIndex]
            queueIndex += 1
            let x = index % width
            let y = index / width

            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbor = ny * width + nx
                    guard !selected[neighbor], scores[neighbor] >= lowThreshold else { continue }
                    selected[neighbor] = true
                    queue.append(neighbor)
                }
            }
        }

        var values = [UInt8](repeating: 0, count: scores.count)
        for index in scores.indices where selected[index] {
            let normalized = clamp(
                (scores[index] - lowThreshold) / max(0.001, 1.0 - lowThreshold),
                0,
                1
            )
            values[index] = UInt8(clamp(88.0 + normalized * 167.0, 0, 255))
        }
        return values
    }

    private func fillEnclosedHoles(
        _ values: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8
    ) -> [UInt8] {
        guard width > 0, height > 0, values.count == width * height else { return values }

        var exterior = [Bool](repeating: false, count: values.count)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        func isBackground(_ index: Int) -> Bool {
            values[index] <= threshold
        }

        func appendExteriorSeed(_ index: Int) {
            guard isBackground(index), !exterior[index] else { return }
            exterior[index] = true
            queue.append(index)
        }

        for x in 0..<width {
            appendExteriorSeed(x)
            appendExteriorSeed((height - 1) * width + x)
        }
        for y in 0..<height {
            appendExteriorSeed(y * width)
            appendExteriorSeed(y * width + width - 1)
        }

        let neighbors = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        var queueIndex = 0
        while queueIndex < queue.count {
            let index = queue[queueIndex]
            queueIndex += 1
            let x = index % width
            let y = index / width
            for (dx, dy) in neighbors {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbor = ny * width + nx
                guard isBackground(neighbor), !exterior[neighbor] else { continue }
                exterior[neighbor] = true
                queue.append(neighbor)
            }
        }

        var output = values
        let filledValue = UInt8(min(255, Int(threshold) + 8))
        for index in values.indices where isBackground(index) && !exterior[index] {
            output[index] = filledValue
        }
        return output
    }

    private func combine(modelMask: MaskGrid, heuristicMask: MaskGrid) -> MaskGrid {
        guard modelMask.width == heuristicMask.width, modelMask.height == heuristicMask.height else {
            return modelMask
        }
        var values = modelMask.values
        for index in values.indices {
            let modelProbability = Float(modelMask.values[index]) / 255.0
            let heuristicProbability = Float(heuristicMask.values[index]) / 255.0
            // Either source may lead when it is strong, but a weak RGB-D result now
            // suppresses a model-only false positive instead of only expanding it.
            let support = clamp((heuristicProbability - 0.18) / 0.55, 0, 1)
            let modelWithSupport = modelProbability * (0.30 + 0.70 * support)
            let heuristicWithSupport = heuristicProbability * (0.72 + 0.28 * modelProbability)
            let fusedProbability = max(modelWithSupport, heuristicWithSupport)
            values[index] = UInt8(clamp(fusedProbability * 255.0, 0, 255))
        }
        return MaskGrid(width: modelMask.width, height: modelMask.height, values: values)
    }

    private func cameraMotionAllowsTemporalSmoothing(_ current: simd_float4x4) -> Bool {
        guard previousMask != nil, let previous = previousCameraTransform else { return true }
        let previousPosition = SIMD3<Float>(
            previous.columns.3.x,
            previous.columns.3.y,
            previous.columns.3.z
        )
        let currentPosition = SIMD3<Float>(
            current.columns.3.x,
            current.columns.3.y,
            current.columns.3.z
        )
        guard simd_length(currentPosition - previousPosition) <= 0.008 else { return false }

        let previousForward = simd_normalize(SIMD3<Float>(
            previous.columns.2.x,
            previous.columns.2.y,
            previous.columns.2.z
        ))
        let currentForward = simd_normalize(SIMD3<Float>(
            current.columns.2.x,
            current.columns.2.y,
            current.columns.2.z
        ))
        let previousUp = simd_normalize(SIMD3<Float>(
            previous.columns.1.x,
            previous.columns.1.y,
            previous.columns.1.z
        ))
        let currentUp = simd_normalize(SIMD3<Float>(
            current.columns.1.x,
            current.columns.1.y,
            current.columns.1.z
        ))
        let cosineTwoDegrees: Float = 0.99939
        return simd_dot(previousForward, currentForward) >= cosineTwoDegrees
            && simd_dot(previousUp, currentUp) >= cosineTwoDegrees
    }

    private func applyTemporalSmoothing(
        to mask: MaskGrid,
        requiredNormalizedROI: CGRect?
    ) -> MaskGrid {
        guard let previousMask,
              previousMask.width == mask.width,
              previousMask.height == mask.height else {
            return mask
        }
        guard foregroundIoU(previousMask, mask, threshold: segmentationThreshold) >= 0.45 else {
            return mask
        }
        var values = mask.values
        for index in values.indices {
            // Blend probabilities on both sides of the boundary. The old version
            // only touched pixels already classified as foreground, so the binary
            // wound edge was effectively a brand-new shape on every frame.
            let smoothed = Float(mask.values[index]) * 0.72
                + Float(previousMask.values[index]) * 0.28
            values[index] = UInt8(clamp(smoothed, 0, 255))
        }
        return keepBestComponent(
            MaskGrid(width: mask.width, height: mask.height, values: values),
            preferredCenterBias: 0.12,
            requiredNormalizedROI: requiredNormalizedROI
        )
    }

    private func foregroundIoU(_ lhs: MaskGrid, _ rhs: MaskGrid, threshold: UInt8) -> Float {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return 0 }

        var intersection = 0
        var union = 0
        for index in lhs.values.indices {
            let lhsForeground = lhs.values[index] > threshold
            let rhsForeground = rhs.values[index] > threshold
            if lhsForeground || rhsForeground {
                union += 1
                if lhsForeground && rhsForeground {
                    intersection += 1
                }
            }
        }

        guard union > 0 else { return 0 }
        return Float(intersection) / Float(union)
    }

    private func keepBestComponent(
        _ mask: MaskGrid,
        preferredCenterBias: Float,
        requiredNormalizedROI: CGRect? = nil
    ) -> MaskGrid {
        let width = mask.width
        let height = mask.height
        let count = width * height
        var visited = [Bool](repeating: false, count: count)
        var bestPixels: [Int] = []
        var bestScore: Float = -.greatestFiniteMagnitude
        let minPixels = max(14, Int(Float(count) * 0.00035))
        let maxPixels = Int(Float(count) * 0.48)

        for start in 0..<count where !visited[start] && mask.values[start] > segmentationThreshold {
            var queue = [start]
            var queueIndex = 0
            visited[start] = true
            var pixels: [Int] = []
            var sumProbability: Float = 0
            var sumX: Float = 0
            var sumY: Float = 0
            var minX = width
            var maxX = 0
            var minY = height
            var maxY = 0
            var roiPixelCount = 0

            while queueIndex < queue.count {
                let index = queue[queueIndex]
                queueIndex += 1
                pixels.append(index)
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                sumX += Float(x)
                sumY += Float(y)
                sumProbability += Float(mask.values[index])
                if let requiredNormalizedROI {
                    let normalizedPoint = CGPoint(
                        x: (CGFloat(x) + 0.5) / CGFloat(width),
                        y: (CGFloat(y) + 0.5) / CGFloat(height)
                    )
                    if requiredNormalizedROI.contains(normalizedPoint) {
                        roiPixelCount += 1
                    }
                }

                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighborIndex = ny * width + nx
                        guard !visited[neighborIndex],
                              mask.values[neighborIndex] > segmentationThreshold else { continue }
                        visited[neighborIndex] = true
                        queue.append(neighborIndex)
                    }
                }
            }

            let pixelCount = pixels.count
            guard pixelCount >= minPixels, pixelCount <= maxPixels else { continue }
            let roiCoverage = Float(roiPixelCount) / Float(max(1, pixelCount))
            if let requiredNormalizedROI {
                // Once a physical wound is locked, never fall back to a component
                // elsewhere in the image. A partial overlap allowance preserves a
                // real wound whose edge extends just beyond the padded lock ROI.
                let requiredOverlap = max(3, Int(Float(pixelCount) * 0.35))
                let centroidPoint = CGPoint(
                    x: CGFloat(sumX / Float(pixelCount) / Float(width)),
                    y: CGFloat(sumY / Float(pixelCount) / Float(height))
                )
                guard roiPixelCount >= requiredOverlap,
                      requiredNormalizedROI.contains(centroidPoint) else { continue }
            }

            let centroidX = sumX / Float(pixelCount) / Float(width)
            let centroidY = sumY / Float(pixelCount) / Float(height)
            let targetCenterX = Float(requiredNormalizedROI?.midX ?? 0.5)
            let targetCenterY = Float(requiredNormalizedROI?.midY ?? 0.5)
            let centerDistance = hypot(centroidX - targetCenterX, centroidY - targetCenterY)
            let probability = sumProbability / Float(max(1, pixelCount) * 255)
            let componentRatio = Float(pixelCount) / Float(count)
            let sizeScore = clamp(sqrt(componentRatio / 0.10), 0, 1)
            let centerScale: Float = {
                guard let requiredNormalizedROI else { return 0.72 }
                return max(
                    0.02,
                    hypot(Float(requiredNormalizedROI.width), Float(requiredNormalizedROI.height)) * 0.60
                )
            }()
            let centerScore = clamp(1.0 - centerDistance / centerScale, 0, 1)
            let bboxRatio = Float((maxX - minX + 1) * (maxY - minY + 1)) / Float(count)
            let borderPenalty: Float = (minX <= 1 || minY <= 1 || maxX >= width - 2 || maxY >= height - 2) ? 0.28 : 0
            let score = 0.62 * probability
                + 0.18 * sizeScore
                + preferredCenterBias * centerScore
                + (requiredNormalizedROI == nil ? 0 : 0.30 * roiCoverage)
                - borderPenalty
                - max(0, bboxRatio - 0.38)

            if score > bestScore {
                bestScore = score
                bestPixels = pixels
            }
        }

        guard !bestPixels.isEmpty else {
            return MaskGrid(
                width: width,
                height: height,
                values: [UInt8](repeating: 0, count: count)
            )
        }
        var values = [UInt8](repeating: 0, count: count)
        for index in bestPixels {
            values[index] = mask.values[index]
        }
        values = morphologyClose(values, width: width, height: height, threshold: segmentationThreshold)
        return MaskGrid(width: width, height: height, values: values)
    }

    private func compute3DMetrics(
        mask: MaskGrid,
        depthGrid: DepthGrid,
        frame: ARFrame,
        boundaryWorldPoints: [SIMD3<Float>]
    ) -> MetricResult? {
        guard mask.width == depthGrid.width, mask.height == depthGrid.height else { return nil }
        guard boundaryWorldPoints.count >= 3 else { return nil }

        let width = mask.width
        let height = mask.height
        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        let sx = Float(width) / max(1, Float(resolution.width))
        let sy = Float(height) / max(1, Float(resolution.height))
        let fx = max(1, intrinsics.columns.0.x * sx)
        let fy = max(1, intrinsics.columns.1.y * sy)
        let cx = intrinsics.columns.2.x * sx
        let cy = intrinsics.columns.2.y * sy

        var allCameraPoints: [(point: SIMD3<Float>, areaM2: Float, index: Int)] = []
        var edgeCameraPoints: [SIMD3<Float>] = []
        var highConfidenceEdgeCameraPoints: [SIMD3<Float>] = []
        var exteriorRing = [Bool](repeating: false, count: width * height)
        var validDepthPixels = 0
        var totalMaskPixels = 0

        // Mark a narrow annulus outside the color-selected boundary. Those points
        // represent intact surrounding skin and are a more stable LiDAR reference
        // plane than pixels on the potentially depressed wound edge itself.
        for y in 0..<height {
            for x in 0..<width where isBoundaryPixel(
                mask: mask,
                x: x,
                y: y,
                threshold: segmentationThreshold
            ) {
                for dy in -6...6 {
                    for dx in -6...6 {
                        let distanceSquared = dx * dx + dy * dy
                        guard distanceSquared >= 4, distanceSquared <= 36 else { continue }
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbor = ny * width + nx
                        if mask.values[neighbor] <= segmentationThreshold {
                            exteriorRing[neighbor] = true
                        }
                    }
                }
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard mask.values[index] > segmentationThreshold else { continue }
                totalMaskPixels += 1
                guard depthGrid.hasDepth[index] else { continue }
                validDepthPixels += 1
                let depthM = depthGrid.depthM[index]
                let point = cameraPoint(x: Float(x) + 0.5, y: Float(y) + 0.5, depthM: depthM, fx: fx, fy: fy, cx: cx, cy: cy)
                let pixelAreaM2 = max(0, depthM * depthM / (fx * fy))
                allCameraPoints.append((point, pixelAreaM2, index))
                if isBoundaryPixel(mask: mask, x: x, y: y, threshold: segmentationThreshold) {
                    edgeCameraPoints.append(point)
                    if depthGrid.highConfidence[index] {
                        highConfidenceEdgeCameraPoints.append(point)
                    }
                }
            }
        }

        var ringCameraPoints: [SIMD3<Float>] = []
        var highConfidenceRingCameraPoints: [SIMD3<Float>] = []
        ringCameraPoints.reserveCapacity(edgeCameraPoints.count * 2)
        highConfidenceRingCameraPoints.reserveCapacity(edgeCameraPoints.count)
        for index in exteriorRing.indices where exteriorRing[index] && depthGrid.hasDepth[index] {
            let x = index % width
            let y = index / width
            let point = cameraPoint(
                x: Float(x) + 0.5,
                y: Float(y) + 0.5,
                depthM: depthGrid.depthM[index],
                fx: fx,
                fy: fy,
                cx: cx,
                cy: cy
            )
            ringCameraPoints.append(point)
            if depthGrid.highConfidence[index] {
                highConfidenceRingCameraPoints.append(point)
            }
        }

        guard allCameraPoints.count >= 8 else { return nil }
        let edgePoints: [SIMD3<Float>] = {
            if highConfidenceRingCameraPoints.count >= 12 {
                return highConfidenceRingCameraPoints
            }
            if ringCameraPoints.count >= 12 {
                return ringCameraPoints
            }
            if highConfidenceEdgeCameraPoints.count >= 8 {
                return highConfidenceEdgeCameraPoints
            }
            if edgeCameraPoints.count >= 8 { return edgeCameraPoints }
            return allCameraPoints.map(\.point)
        }()
        guard let plane = fitPlane(to: edgePoints) else { return nil }

        let highConfidenceCameraPoints = allCameraPoints.filter {
            depthGrid.highConfidence[$0.index]
        }
        let measurementCameraPoints = highConfidenceCameraPoints.count >= max(8, allCameraPoints.count / 3)
            ? highConfidenceCameraPoints
            : allCameraPoints

        var signedDepths: [(signed: Float, areaM2: Float, point: SIMD3<Float>, world: SIMD3<Float>)] = []
        signedDepths.reserveCapacity(measurementCameraPoints.count)
        for item in measurementCameraPoints {
            let signed = simd_dot(item.point - plane.origin, plane.normal)
            guard signed.isFinite else { continue }
            let world = worldPoint(fromCameraPoint: item.point, frame: frame)
            signedDepths.append((signed, item.areaM2, item.point, world))
        }

        // Camera-space Z points toward the viewer while measured depth extends
        // along -Z. `fitPlane` always returns a +Z-facing normal, so a wound cavity
        // is consistently the negative side. Picking the larger tail could flip
        // the cavity direction from frame to frame when the surface was shallow.
        let depressionSign: Float = -1

        var sampledAreaM2: Float = 0
        var sampledVolumeM3: Float = 0
        var maxDepthM: Float = 0
        var deepestWorldPoint: SIMD3<Float>?
        var inlierCount = 0

        for sample in signedDepths {
            sampledAreaM2 += sample.areaM2
            let depressionM = sample.signed * depressionSign
            guard depressionM.isFinite, depressionM > 0.00025, depressionM < 0.09 else { continue }
            let weightedDepth = min(depressionM, 0.09)
            sampledVolumeM3 += sample.areaM2 * weightedDepth
            inlierCount += 1
            if weightedDepth > maxDepthM {
                maxDepthM = weightedDepth
                deepestWorldPoint = sample.world
            }
        }

        var areaM2 = sampledAreaM2
        var volumeM3 = sampledVolumeM3
        let fallbackPerimeterM = perimeter(points: boundaryWorldPoints)
        var perimeterM = fallbackPerimeterM

        if let planeGeometry = referencePlanePolygonMetrics(
            boundaryWorldPoints: boundaryWorldPoints,
            plane: plane,
            frame: frame
        ) {
            perimeterM = planeGeometry.perimeterM
            areaM2 = planeGeometry.areaM2

            // Pixel footprints are camera-facing projected areas. Scale both area and
            // integrated volume by the same factor so an oblique fitted surface does not
            // change area without making the corresponding volume correction. The full
            // contour remains the authoritative area even when sparse depth support makes
            // the volume scale unreliable.
            if sampledAreaM2 > 0 {
                let areaScale = planeGeometry.areaM2 / sampledAreaM2
                if areaScale.isFinite, areaScale >= 0.25, areaScale <= 4.0 {
                    volumeM3 = sampledVolumeM3 * areaScale
                } else {
                    volumeM3 = 0
                }
            }
        }

        let depthCoverage = Float(validDepthPixels) / Float(max(1, totalMaskPixels))
        let support = Float(edgePoints.count) / Float(max(1, totalMaskPixels))

        return MetricResult(
            areaCm2: max(0, areaM2 * 10_000.0),
            volumeCm3: max(0, volumeM3 * 1_000_000.0),
            maxDepthMm: max(0, maxDepthM * 1_000.0),
            perimeterCm: max(0, perimeterM * 100.0),
            deepestWorldPoint: deepestWorldPoint,
            plane: Plane(
                origin: worldPoint(fromCameraPoint: plane.origin, frame: frame),
                normal: simd_normalize(SIMD3<Float>(
                    frame.camera.transform.columns.0.x * plane.normal.x + frame.camera.transform.columns.1.x * plane.normal.y + frame.camera.transform.columns.2.x * plane.normal.z,
                    frame.camera.transform.columns.0.y * plane.normal.x + frame.camera.transform.columns.1.y * plane.normal.y + frame.camera.transform.columns.2.y * plane.normal.z,
                    frame.camera.transform.columns.0.z * plane.normal.x + frame.camera.transform.columns.1.z * plane.normal.y + frame.camera.transform.columns.2.z * plane.normal.z
                ))
            ),
            sampledPointCount: max(0, inlierCount),
            validDepthPixelCount: validDepthPixels,
            depthCoverage: depthCoverage,
            planeSupport: support
        )
    }

    private func referencePlanePolygonMetrics(
        boundaryWorldPoints: [SIMD3<Float>],
        plane: Plane,
        frame: ARFrame
    ) -> (areaM2: Float, perimeterM: Float)? {
        guard boundaryWorldPoints.count >= 3 else { return nil }
        let normalLength = simd_length(plane.normal)
        guard normalLength.isFinite, normalLength > 0.000001 else { return nil }
        let normal = plane.normal / normalLength

        let referenceAxis: SIMD3<Float> = abs(normal.z) < 0.9
            ? SIMD3<Float>(0, 0, 1)
            : SIMD3<Float>(0, 1, 0)
        let uRaw = simd_cross(referenceAxis, normal)
        let uLength = simd_length(uRaw)
        guard uLength.isFinite, uLength > 0.000001 else { return nil }
        let u = uRaw / uLength
        let v = simd_normalize(simd_cross(normal, u))
        guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { return nil }

        let cameraFromWorld = simd_inverse(frame.camera.transform)
        let projected: [SIMD2<Float>] = boundaryWorldPoints.compactMap { worldPoint in
            let camera4 = cameraFromWorld * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
            let cameraPoint = SIMD3<Float>(camera4.x, camera4.y, camera4.z)
            guard cameraPoint.x.isFinite, cameraPoint.y.isFinite, cameraPoint.z.isFinite else { return nil }
            let delta = cameraPoint - plane.origin
            let point = SIMD2<Float>(simd_dot(delta, u), simd_dot(delta, v))
            return point.x.isFinite && point.y.isFinite ? point : nil
        }
        guard projected.count >= 3 else { return nil }

        var doubledArea: Float = 0
        var perimeterM: Float = 0
        for index in projected.indices {
            let current = projected[index]
            let next = projected[(index + 1) % projected.count]
            doubledArea += current.x * next.y - next.x * current.y
            perimeterM += simd_length(next - current)
        }
        let areaM2 = abs(doubledArea) * 0.5
        guard areaM2.isFinite, areaM2 > 0.00000001,
              perimeterM.isFinite, perimeterM > 0 else {
            return nil
        }
        return (areaM2, perimeterM)
    }

    private func boundaryPolygon(
        from mask: MaskGrid,
        pixelBuffer: CVPixelBuffer,
        threshold: UInt8
    ) -> [CGPoint] {
        if let ordered = visionBoundaryPolygon(
            from: mask,
            pixelBuffer: pixelBuffer
        ), ordered.count >= 3 {
            return ordered
        }
        return fallbackBoundaryPolygon(from: mask, threshold: threshold)
    }

    private func visionBoundaryPolygon(
        from mask: MaskGrid,
        pixelBuffer: CVPixelBuffer
    ) -> [CGPoint]? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = false
        request.maximumImageDimension = max(mask.width, mask.height)

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else {
            return nil
        }

        func normalizedArea(_ contour: VNContour) -> Float {
            let points = contour.normalizedPoints
            guard points.count >= 3 else { return 0 }
            var area: Float = 0
            for index in points.indices {
                let current = points[index]
                let next = points[(index + 1) % points.count]
                area += current.x * next.y - next.x * current.y
            }
            return abs(area) * 0.5
        }

        guard let contour = observation.topLevelContours
            .filter({ $0.pointCount >= 3 })
            .max(by: { normalizedArea($0) < normalizedArea($1) }) else {
            return nil
        }

        var points = contour.normalizedPoints.compactMap { point -> CGPoint? in
            let x = CGFloat(point.x)
            let y = 1.0 - CGFloat(point.y)
            guard x.isFinite, y.isFinite else { return nil }
            return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        }
        guard points.count >= 3 else { return nil }

        if points.count > 3,
           let first = points.first,
           let last = points.last,
           hypot(first.x - last.x, first.y - last.y) < 0.0001 {
            points.removeLast()
        }
        guard points.count >= 3 else { return nil }

        let maximumPointCount = 180
        guard points.count > maximumPointCount else { return points }
        let sampleStep = Double(points.count) / Double(maximumPointCount)
        return (0..<maximumPointCount).map { index in
            points[min(points.count - 1, Int((Double(index) * sampleStep).rounded(.down)))]
        }
    }

    private func fallbackBoundaryPolygon(from mask: MaskGrid, threshold: UInt8) -> [CGPoint] {
        let width = mask.width
        let height = mask.height
        var points: [CGPoint] = []
        points.reserveCapacity(512)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where isBoundaryPixel(mask: mask, x: x, y: y, threshold: threshold) {
                points.append(CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: (CGFloat(y) + 0.5) / CGFloat(height)
                ))
            }
        }
        guard points.count >= 3 else { return [] }

        let centroid = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let center = CGPoint(x: centroid.x / CGFloat(points.count), y: centroid.y / CGFloat(points.count))
        let ordered = points.sorted {
            atan2($0.y - center.y, $0.x - center.x) < atan2($1.y - center.y, $1.x - center.x)
        }

        let targetCount = min(180, max(36, ordered.count / 3))
        let step = max(1, ordered.count / targetCount)
        return stride(from: 0, to: ordered.count, by: step).map { ordered[$0] }
    }

    private func screenPoint(
        fromCameraNormalized point: CGPoint,
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation
    ) -> CGPoint? {
        let transform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let viewNormalized = point.applying(transform)
        guard viewNormalized.x.isFinite, viewNormalized.y.isFinite else { return nil }
        return CGPoint(x: viewNormalized.x * viewportSize.width, y: viewNormalized.y * viewportSize.height)
    }

    private func worldPoint(
        fromCameraNormalized point: CGPoint,
        depthGrid: DepthGrid,
        frame: ARFrame
    ) -> SIMD3<Float>? {
        let width = depthGrid.width
        let height = depthGrid.height
        let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
        guard let depthM = nearestDepth(in: depthGrid, x: x, y: y) else { return nil }

        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        let sx = Float(width) / max(1, Float(resolution.width))
        let sy = Float(height) / max(1, Float(resolution.height))
        let fx = max(1, intrinsics.columns.0.x * sx)
        let fy = max(1, intrinsics.columns.1.y * sy)
        let cx = intrinsics.columns.2.x * sx
        let cy = intrinsics.columns.2.y * sy
        let camera = cameraPoint(x: Float(x) + 0.5, y: Float(y) + 0.5, depthM: depthM, fx: fx, fy: fy, cx: cx, cy: cy)
        return worldPoint(fromCameraPoint: camera, frame: frame)
    }

    private func completeWorldBoundary(
        fromCameraNormalized points: [CGPoint],
        depthGrid: DepthGrid,
        frame: ARFrame
    ) -> [SIMD3<Float>]? {
        guard points.count >= 3 else { return nil }
        let width = depthGrid.width
        let height = depthGrid.height
        var depths: [Float?] = points.map { point in
            let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
            let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
            let index = y * width + x
            guard depthGrid.hasDepth[index] else { return nil }
            let depthM = depthGrid.depthM[index]
            return depthM.isFinite && depthM > 0.02 && depthM < 5.0 ? depthM : nil
        }
        let validCount = depths.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
        guard Float(validCount) / Float(points.count) >= 0.82 else { return nil }

        // A short missing depth run can be filled along each original camera ray;
        // a long arc must be rejected rather than silently closing it with a chord.
        var largestMissingRun = 0
        var currentMissingRun = 0
        for index in 0..<(points.count * 2) {
            if depths[index % points.count] == nil {
                currentMissingRun += 1
                largestMissingRun = max(largestMissingRun, min(points.count, currentMissingRun))
            } else {
                currentMissingRun = 0
            }
        }
        let maximumInterpolatedRun = max(2, Int(ceil(Float(points.count) * 0.06)))
        guard largestMissingRun <= maximumInterpolatedRun else { return nil }

        for index in depths.indices where depths[index] == nil {
            var previous = index
            var previousDistance = 0
            repeat {
                previous = (previous - 1 + depths.count) % depths.count
                previousDistance += 1
            } while depths[previous] == nil && previousDistance < depths.count

            var next = index
            var nextDistance = 0
            repeat {
                next = (next + 1) % depths.count
                nextDistance += 1
            } while depths[next] == nil && nextDistance < depths.count

            guard let previousDepth = depths[previous], let nextDepth = depths[next] else { return nil }
            let fraction = Float(previousDistance)
                / Float(max(1, previousDistance + nextDistance))
            depths[index] = previousDepth + (nextDepth - previousDepth) * fraction
        }

        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        let sx = Float(width) / max(1, Float(resolution.width))
        let sy = Float(height) / max(1, Float(resolution.height))
        let fx = max(1, intrinsics.columns.0.x * sx)
        let fy = max(1, intrinsics.columns.1.y * sy)
        let cx = intrinsics.columns.2.x * sx
        let cy = intrinsics.columns.2.y * sy

        var worldPoints: [SIMD3<Float>] = []
        worldPoints.reserveCapacity(points.count)
        for (point, depth) in zip(points, depths) {
            guard let depth else { return nil }
            let camera = cameraPoint(
                x: Float(point.x) * Float(width),
                y: Float(point.y) * Float(height),
                depthM: depth,
                fx: fx,
                fy: fy,
                cx: cx,
                cy: cy
            )
            worldPoints.append(worldPoint(fromCameraPoint: camera, frame: frame))
        }
        return worldPoints
    }

    private func nearestDepth(in depthGrid: DepthGrid, x: Int, y: Int) -> Float? {
        let index = y * depthGrid.width + x
        // Preserve the point's own camera ray whenever it has a valid depth. Nearby
        // high-confidence skin pixels must not displace a valid wound-edge sample.
        if depthGrid.hasDepth[index] {
            return depthGrid.depthM[index]
        }
        for radius in 1...4 {
            var values: [Float] = []
            for yy in max(0, y - radius)...min(depthGrid.height - 1, y + radius) {
                for xx in max(0, x - radius)...min(depthGrid.width - 1, x + radius) {
                    let neighbor = yy * depthGrid.width + xx
                    guard depthGrid.hasDepth[neighbor], depthGrid.highConfidence[neighbor] else { continue }
                    values.append(depthGrid.depthM[neighbor])
                }
            }
            if !values.isEmpty {
                values.sort()
                return values[values.count / 2]
            }
        }
        for radius in 1...4 {
            var values: [Float] = []
            for yy in max(0, y - radius)...min(depthGrid.height - 1, y + radius) {
                for xx in max(0, x - radius)...min(depthGrid.width - 1, x + radius) {
                    let neighbor = yy * depthGrid.width + xx
                    guard depthGrid.hasDepth[neighbor] else { continue }
                    values.append(depthGrid.depthM[neighbor])
                }
            }
            if !values.isEmpty {
                values.sort()
                return values[values.count / 2]
            }
        }
        return nil
    }

    private func cameraPoint(x: Float, y: Float, depthM: Float, fx: Float, fy: Float, cx: Float, cy: Float) -> SIMD3<Float> {
        let xCamera = (x - cx) / fx * depthM
        let yCamera = (cy - y) / fy * depthM
        return SIMD3<Float>(xCamera, yCamera, -depthM)
    }

    private func worldPoint(fromCameraPoint point: SIMD3<Float>, frame: ARFrame) -> SIMD3<Float> {
        let world = frame.camera.transform * SIMD4<Float>(point.x, point.y, point.z, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private func fitPlane(to points: [SIMD3<Float>]) -> Plane? {
        guard points.count >= 3 else { return nil }
        guard let initial = leastSquaresPlane(to: points) else { return nil }

        let residuals = points
            .map { abs(simd_dot($0 - initial.origin, initial.normal)) }
            .filter(\.isFinite)
            .sorted()
        guard !residuals.isEmpty else { return initial }
        let medianResidual = percentile(residuals, 0.50)
        let deviations = residuals.map { abs($0 - medianResidual) }.sorted()
        let mad = percentile(deviations, 0.50)
        let tolerance = max(0.0015, medianResidual + mad * 3.0)
        let inliers = points.filter {
            abs(simd_dot($0 - initial.origin, initial.normal)) <= tolerance
        }
        guard inliers.count >= max(6, points.count / 2), inliers.count < points.count else {
            return initial
        }
        return leastSquaresPlane(to: inliers) ?? initial
    }

    private func leastSquaresPlane(to points: [SIMD3<Float>]) -> Plane? {
        guard points.count >= 3 else { return nil }
        let origin = points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)

        var sx: Float = 0
        var sy: Float = 0
        var sz: Float = 0
        var sxx: Float = 0
        var sxy: Float = 0
        var syy: Float = 0
        var sxz: Float = 0
        var syz: Float = 0

        for point in points {
            sx += point.x
            sy += point.y
            sz += point.z
            sxx += point.x * point.x
            sxy += point.x * point.y
            syy += point.y * point.y
            sxz += point.x * point.z
            syz += point.y * point.z
        }

        let n = Float(points.count)
        let matrix = (
            SIMD3<Float>(sxx, sxy, sx),
            SIMD3<Float>(sxy, syy, sy),
            SIMD3<Float>(sx, sy, n)
        )
        let rhs = SIMD3<Float>(sxz, syz, sz)
        guard let solution = solve3x3(matrix, rhs: rhs) else {
            let fallbackNormal = simd_normalize(SIMD3<Float>(0, 0, 1))
            return Plane(origin: origin, normal: fallbackNormal)
        }
        let normal = simd_normalize(SIMD3<Float>(-solution.x, -solution.y, 1))
        guard normal.x.isFinite, normal.y.isFinite, normal.z.isFinite else { return nil }
        return Plane(origin: origin, normal: normal)
    }

    private func solve3x3(_ matrix: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>), rhs: SIMD3<Float>) -> SIMD3<Float>? {
        let a = matrix.0.x, b = matrix.0.y, c = matrix.0.z
        let d = matrix.1.x, e = matrix.1.y, f = matrix.1.z
        let g = matrix.2.x, h = matrix.2.y, i = matrix.2.z
        let determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(determinant) > 1e-8 else { return nil }

        let dx = rhs.x * (e * i - f * h) - b * (rhs.y * i - f * rhs.z) + c * (rhs.y * h - e * rhs.z)
        let dy = a * (rhs.y * i - f * rhs.z) - rhs.x * (d * i - f * g) + c * (d * rhs.z - rhs.y * g)
        let dz = a * (e * rhs.z - rhs.y * h) - b * (d * rhs.z - rhs.y * g) + rhs.x * (d * h - e * g)
        return SIMD3<Float>(dx / determinant, dy / determinant, dz / determinant)
    }

    private func isBoundaryPixel(mask: MaskGrid, x: Int, y: Int, threshold: UInt8) -> Bool {
        let width = mask.width
        let height = mask.height
        let index = y * width + x
        guard x >= 0, x < width, y >= 0, y < height, mask.values[index] > threshold else { return false }
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = x + dx
                let ny = y + dy
                if nx < 0 || nx >= width || ny < 0 || ny >= height { return true }
                if mask.values[ny * width + nx] <= threshold { return true }
            }
        }
        return false
    }

    private func boundingRectForMask(_ mask: MaskGrid, threshold: UInt8) -> CGRect {
        var minX = mask.width
        var maxX = 0
        var minY = mask.height
        var maxY = 0
        var found = false

        for y in 0..<mask.height {
            for x in 0..<mask.width {
                guard mask.values[y * mask.width + x] > threshold else { continue }
                found = true
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard found else { return .zero }
        return CGRect(
            x: CGFloat(minX) / CGFloat(mask.width),
            y: CGFloat(minY) / CGFloat(mask.height),
            width: CGFloat(max(1, maxX - minX + 1)) / CGFloat(mask.width),
            height: CGFloat(max(1, maxY - minY + 1)) / CGFloat(mask.height)
        )
    }

    private func computeColorFeatures(mask: MaskGrid, colorGrid: ColorGrid) -> WoundColorFeatures {
        var lSum: Float = 0
        var aSum: Float = 0
        var bSum: Float = 0
        var rednessSum: Float = 0
        var count: Float = 0

        for index in mask.values.indices where mask.values[index] > segmentationThreshold {
            lSum += colorGrid.lStar[index]
            aSum += colorGrid.aStar[index]
            bSum += colorGrid.bStar[index]
            rednessSum += colorGrid.rednessIndex[index]
            count += 1
        }

        guard count > 0 else {
            return WoundColorFeatures(meanLAB: (0, 0, 0), rednessIndex: 0, tissueClassification: .unknown)
        }

        let meanL = lSum / count
        let meanA = aSum / count
        let meanB = bSum / count
        let redness = rednessSum / count

        let tissue: TissueType
        if meanL < 26 {
            tissue = .eschar
        } else if meanB > 22, meanL > 42 {
            tissue = .slough
        } else if redness > 0.14 || meanA > 22 {
            tissue = .granulation
        } else if meanL > 54, meanA < 18 {
            tissue = .epithelializing
        } else {
            tissue = .mixed
        }

        return WoundColorFeatures(meanLAB: (meanL, meanA, meanB), rednessIndex: redness, tissueClassification: tissue)
    }

    private func computeConfidence(
        mask: MaskGrid,
        source: MaskSource,
        metrics: MetricResult,
        depthGrid: DepthGrid
    ) -> Float {
        let sourceScore: Float
        switch source {
        case .coreML:
            sourceScore = 0.88
        case .fused:
            sourceScore = 0.82
        case .heuristic:
            sourceScore = 0.62
        }

        let maskRatio = mask.foregroundRatio(threshold: segmentationThreshold)
        let shapeScore = maskRatio >= 0.0008 && maskRatio <= 0.24 ? 0.85 : 0.55
        let depthScore = clamp(metrics.depthCoverage, 0, 1)
        let planeScore = clamp(metrics.planeSupport * 3.2, 0, 1)
        let confidenceScore = clamp(depthGrid.confidenceMean, 0, 1)
        let depthMeasurementScore: Float = metrics.maxDepthMm > 0.4 || metrics.volumeCm3 > 0 ? 1.0 : 0.48

        let raw = 0.26 * sourceScore
            + 0.20 * Float(shapeScore)
            + 0.26 * depthScore
            + 0.16 * planeScore
            + 0.08 * confidenceScore
            + 0.04 * depthMeasurementScore
        return clamp(raw, 0, source == .heuristic ? 0.74 : 0.96)
    }

    private func maskGrid(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MaskGrid? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        if format == kCVPixelFormatType_OneComponent8 {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            var values = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height {
                let sy = min(sourceHeight - 1, Int((Float(y) + 0.5) / Float(height) * Float(sourceHeight)))
                let row = base.advanced(by: sy * bytesPerRow)
                for x in 0..<width {
                    let sx = min(sourceWidth - 1, Int((Float(x) + 0.5) / Float(width) * Float(sourceWidth)))
                    values[y * width + x] = row.load(fromByteOffset: sx, as: UInt8.self)
                }
            }
            return MaskGrid(width: width, height: height, values: values)
        }

        if format == kCVPixelFormatType_OneComponent32Float || format == kCVPixelFormatType_DepthFloat32 {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            var values = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height {
                let sy = min(sourceHeight - 1, Int((Float(y) + 0.5) / Float(height) * Float(sourceHeight)))
                let row = base.advanced(by: sy * bytesPerRow)
                for x in 0..<width {
                    let sx = min(sourceWidth - 1, Int((Float(x) + 0.5) / Float(width) * Float(sourceWidth)))
                    let raw = row.load(fromByteOffset: sx * MemoryLayout<Float>.size, as: Float.self)
                    let prob = raw < 0 || raw > 1 ? sigmoid(raw) : raw
                    values[y * width + x] = UInt8(clamp(prob * 255.0, 0, 255))
                }
            }
            return MaskGrid(width: width, height: height, values: values)
        }

        guard let bytes = rgbaBytes(from: pixelBuffer, width: width, height: height) else { return nil }
        var values = [UInt8](repeating: 0, count: width * height)
        for index in 0..<values.count {
            let byteIndex = index * 4
            let r = Float(bytes[byteIndex])
            let g = Float(bytes[byteIndex + 1])
            let b = Float(bytes[byteIndex + 2])
            values[index] = UInt8(clamp((r + g + b) / 3.0, 0, 255))
        }
        return MaskGrid(width: width, height: height, values: values)
    }

    private func maskGrid(from array: MLMultiArray, width: Int, height: Int) -> MaskGrid? {
        guard array.count > 0 else { return nil }
        let shape = array.shape.map { $0.intValue }
        let outHeight = shape.count >= 2 ? shape[shape.count - 2] : height
        let outWidth = shape.count >= 1 ? shape[shape.count - 1] : width
        guard outWidth > 0, outHeight > 0 else { return nil }

        var sourceValues = [Float](repeating: 0, count: outWidth * outHeight)
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                let rawIndex = y * outWidth + x
                let value = arrayValue(array, flatIndex: rawIndex)
                sourceValues[rawIndex] = value < 0 || value > 1 ? sigmoid(value) : value
            }
        }

        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let sy = min(outHeight - 1, Int((Float(y) + 0.5) / Float(height) * Float(outHeight)))
            for x in 0..<width {
                let sx = min(outWidth - 1, Int((Float(x) + 0.5) / Float(width) * Float(outWidth)))
                values[y * width + x] = UInt8(clamp(sourceValues[sy * outWidth + sx] * 255.0, 0, 255))
            }
        }

        return MaskGrid(width: width, height: height, values: values)
    }

    private func arrayValue(_ array: MLMultiArray, flatIndex: Int) -> Float {
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return pointer[min(flatIndex, array.count - 1)]
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            return Float(pointer[min(flatIndex, array.count - 1)])
        case .float16:
            return array[min(flatIndex, array.count - 1)].floatValue
        case .int32:
            let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: array.count)
            return Float(pointer[min(flatIndex, array.count - 1)])
        default:
            return array[min(flatIndex, array.count - 1)].floatValue
        }
    }

    private func makeMaskPixelBuffer(
        from mask: MaskGrid,
        binaryThreshold: UInt8? = nil
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            mask.width,
            mask.height,
            kCVPixelFormatType_OneComponent8,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<mask.height {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<mask.width {
                let value = mask.values[y * mask.width + x]
                let outputValue: UInt8
                if let binaryThreshold {
                    outputValue = value > binaryThreshold ? 255 : 0
                } else {
                    outputValue = value
                }
                row.storeBytes(of: outputValue, toByteOffset: x, as: UInt8.self)
            }
        }
        return pixelBuffer
    }

    private func morphologyClose(_ values: [UInt8], width: Int, height: Int, threshold: UInt8) -> [UInt8] {
        erode(dilate(values, width: width, height: height, threshold: threshold), width: width, height: height, threshold: threshold)
    }

    private func dilate(_ values: [UInt8], width: Int, height: Int, threshold: UInt8) -> [UInt8] {
        var output = values
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if values[index] > threshold { continue }
                var best: UInt8 = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        best = max(best, values[ny * width + nx])
                    }
                }
                if best > threshold { output[index] = best }
            }
        }
        return output
    }

    private func erode(_ values: [UInt8], width: Int, height: Int, threshold: UInt8) -> [UInt8] {
        var output = values
        for y in 0..<height {
            for x in 0..<width where values[y * width + x] > threshold {
                var keep = true
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx
                        let ny = y + dy
                        if nx < 0 || nx >= width || ny < 0 || ny >= height || values[ny * width + nx] <= threshold {
                            keep = false
                        }
                    }
                }
                if !keep { output[y * width + x] = 0 }
            }
        }
        return output
    }

    private func boxMean(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var integral = [Float](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum: Float = 0
            for x in 0..<width {
                rowSum += values[y * width + x]
                integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + rowSum
            }
        }

        var output = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius)
            let y1 = min(height - 1, y + radius)
            for x in 0..<width {
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                let a = integral[y0 * (width + 1) + x0]
                let b = integral[y0 * (width + 1) + x1 + 1]
                let c = integral[(y1 + 1) * (width + 1) + x0]
                let d = integral[(y1 + 1) * (width + 1) + x1 + 1]
                let area = Float((x1 - x0 + 1) * (y1 - y0 + 1))
                output[y * width + x] = (d - b - c + a) / max(1, area)
            }
        }
        return output
    }

    private func boxMean(
        _ values: [Float],
        valid: [Bool],
        width: Int,
        height: Int,
        radius: Int,
        fallback: Float
    ) -> [Float] {
        guard values.count == width * height, valid.count == values.count else {
            return [Float](repeating: fallback, count: max(0, width * height))
        }

        let integralWidth = width + 1
        var sumIntegral = [Float](repeating: 0, count: integralWidth * (height + 1))
        var countIntegral = [Int](repeating: 0, count: integralWidth * (height + 1))

        for y in 0..<height {
            var rowSum: Float = 0
            var rowCount = 0
            for x in 0..<width {
                let sourceIndex = y * width + x
                if valid[sourceIndex] {
                    rowSum += values[sourceIndex]
                    rowCount += 1
                }
                let integralIndex = (y + 1) * integralWidth + x + 1
                sumIntegral[integralIndex] = sumIntegral[y * integralWidth + x + 1] + rowSum
                countIntegral[integralIndex] = countIntegral[y * integralWidth + x + 1] + rowCount
            }
        }

        var output = [Float](repeating: fallback, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius)
            let y1 = min(height - 1, y + radius) + 1
            for x in 0..<width {
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius) + 1
                let sum = sumIntegral[y1 * integralWidth + x1]
                    - sumIntegral[y0 * integralWidth + x1]
                    - sumIntegral[y1 * integralWidth + x0]
                    + sumIntegral[y0 * integralWidth + x0]
                let sampleCount = countIntegral[y1 * integralWidth + x1]
                    - countIntegral[y0 * integralWidth + x1]
                    - countIntegral[y1 * integralWidth + x0]
                    + countIntegral[y0 * integralWidth + x0]
                if sampleCount > 0 {
                    output[y * width + x] = sum / Float(sampleCount)
                }
            }
        }
        return output
    }

    private func isDepthConfidenceUsable(_ value: UInt8, maximumSeen: UInt8) -> Bool {
        if maximumSeen <= 2 {
            return value >= 1
        }
        return value >= 128
    }

    private func normalizedConfidence(_ value: UInt8, maximumSeen: UInt8) -> Float {
        if maximumSeen == 0 { return 1 }
        if maximumSeen <= 2 {
            return Float(value) / 2.0
        }
        return Float(value) / 255.0
    }

    private func perimeter(points: [SIMD3<Float>]) -> Float {
        guard points.count >= 2 else { return 0 }
        var sum: Float = 0
        for index in 0..<points.count {
            sum += simd_length(points[(index + 1) % points.count] - points[index])
        }
        return sum
    }

    private func srgbToLinear(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private func rgbToLAB(r: Float, g: Float, b: Float) -> (L: Float, a: Float, b: Float) {
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

        func f(_ t: Float) -> Float {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
        }

        let fx = f(x)
        let fy = f(y)
        let fz = f(z)
        return (
            L: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    private func sigmoid(_ value: Float) -> Float {
        1.0 / (1.0 + exp(-value))
    }

    private func percentile(_ sortedValues: [Float], _ fraction: Float) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        if sortedValues.count == 1 { return sortedValues[0] }
        let clamped = min(max(fraction, 0), 1)
        let rawIndex = clamped * Float(sortedValues.count - 1)
        let lowerIndex = Int(floor(rawIndex))
        let upperIndex = min(sortedValues.count - 1, lowerIndex + 1)
        let t = rawIndex - Float(lowerIndex)
        return sortedValues[lowerIndex] * (1 - t) + sortedValues[upperIndex] * t
    }

    private func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(max(value, lower), upper)
    }
}
