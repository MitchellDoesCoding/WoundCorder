import ARKit
import CoreImage
import CoreML
import Foundation
import UIKit
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
    let skinPlaneOrigin: SIMD3<Float>
    let skinPlaneNormal: SIMD3<Float>
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
    let skinToneITA: Float
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

    private struct MaskGrid {
        let width: Int
        let height: Int
        var values: [UInt8]

        var foregroundRatio: Float {
            guard !values.isEmpty else { return 0 }
            let count = values.reduce(0) { $0 + ($1 > 76 ? 1 : 0) }
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

    private let channelMeans: [Float] = [0.485, 0.456, 0.406, 0.50, 0.50, 0.50, 0.00, 0.12]
    private let channelStds: [Float] = [0.229, 0.224, 0.225, 0.22, 0.20, 0.20, 0.08, 0.18]

    init(modelName: String = "WoundSegmentation") {
        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: compiledURL)
        } else if let sourceURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodel"),
                  let compiledURL = try? MLModel.compileModel(at: sourceURL) {
            model = try? MLModel(contentsOf: compiledURL)
        } else {
            model = nil
        }
    }

    func resetTemporalState() {
        previousMask = nil
    }

    func segment(
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation
    ) -> WoundSegmentationResult? {
        guard viewportSize.width > 2, viewportSize.height > 2 else { return nil }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
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
        let heuristicMask = makeHeuristicMask(colorGrid: colorGrid, depthGrid: depthGrid)

        let maskSource: MaskSource
        let fusedMask: MaskGrid
        if let modelMask, modelMask.foregroundRatio >= 0.0005, modelMask.foregroundRatio <= 0.55 {
            fusedMask = keepBestComponent(
                combine(modelMask: modelMask, heuristicMask: heuristicMask),
                preferredCenterBias: 0.14
            )
            maskSource = .fused
        } else {
            fusedMask = keepBestComponent(heuristicMask, preferredCenterBias: 0.20)
            maskSource = .heuristic
        }

        let temporalMask = applyTemporalSmoothing(to: fusedMask)
        previousMask = temporalMask

        guard temporalMask.foregroundRatio >= 0.0004, temporalMask.foregroundRatio <= 0.55 else { return nil }
        guard let maskBuffer = makeMaskPixelBuffer(from: temporalMask) else { return nil }

        let normalizedBoundary = boundaryPolygon(from: temporalMask, threshold: segmentationThreshold)
        guard normalizedBoundary.count >= 3 else { return nil }

        let screenBoundary = normalizedBoundary.compactMap {
            screenPoint(fromCameraNormalized: $0, frame: frame, viewportSize: viewportSize, orientation: orientation)
        }
        guard screenBoundary.count >= 3 else { return nil }

        let worldBoundary = normalizedBoundary.compactMap {
            worldPoint(fromCameraNormalized: $0, depthGrid: depthGrid, frame: frame)
        }
        guard worldBoundary.count >= 3 else { return nil }

        let metrics = compute3DMetrics(
            mask: temporalMask,
            depthGrid: depthGrid,
            frame: frame,
            boundaryWorldPoints: worldBoundary
        )
        guard let metrics else { return nil }

        let boundingRect = boundingRectForMask(temporalMask, threshold: segmentationThreshold)
        let colorFeatures = computeColorFeatures(mask: temporalMask, colorGrid: colorGrid)
        let skinITA = computeSkinITA(mask: temporalMask, colorGrid: colorGrid, boundingRect: boundingRect)
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
            skinPlaneOrigin: metrics.plane.origin,
            skinPlaneNormal: metrics.plane.normal,
            sampledPointCount: metrics.sampledPointCount,
            validDepthPixelCount: metrics.validDepthPixelCount
        )

        return WoundSegmentationResult(
            mask: maskBuffer,
            boundingRect: boundingRect,
            areaCm2: metrics.areaCm2,
            volumeCm3: metrics.volumeCm3,
            maxDepthMm: metrics.maxDepthMm,
            perimeter: metrics.perimeterCm,
            confidence: confidence,
            skinToneITA: skinITA,
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

    private func makeHeuristicMask(colorGrid: ColorGrid, depthGrid: DepthGrid) -> MaskGrid {
        let width = colorGrid.width
        let height = colorGrid.height
        let count = width * height

        let localL = boxMean(colorGrid.lStar, width: width, height: height, radius: 14)
        let localA = boxMean(colorGrid.aStar, width: width, height: height, radius: 14)
        let localB = boxMean(colorGrid.bStar, width: width, height: height, radius: 14)
        let localDepth = boxMean(depthGrid.depthM, width: width, height: height, radius: 12)

        var scores = [Float](repeating: 0, count: count)
        scores.reserveCapacity(count)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let deltaL = colorGrid.lStar[index] - localL[index]
                let deltaA = colorGrid.aStar[index] - localA[index]
                let deltaB = colorGrid.bStar[index] - localB[index]
                let colorDistance = sqrt(deltaL * deltaL + deltaA * deltaA + deltaB * deltaB)
                let localContrast = clamp(colorDistance / 42.0, 0, 1)

                let redness = clamp((colorGrid.rednessIndex[index] + 0.08) / 0.30, 0, 1)
                let yellowSlough = clamp((deltaB + 10.0) / 30.0, 0, 1)
                let darkEschar = clamp((-deltaL - 3.0) / 30.0, 0, 1)
                let tissueCue = max(redness, max(yellowSlough, darkEschar))

                let depthResidual = depthGrid.depthM[index] - localDepth[index]
                let depressionCue = clamp(depthResidual / 0.026, 0, 1)
                let depthCue = depthGrid.hasDepth[index] ? max(depressionCue, depthGrid.normalMagnitude[index] * 0.45) : 0

                let nx = (Float(x) + 0.5) / Float(width)
                let ny = (Float(y) + 0.5) / Float(height)
                let centerDistance = hypot(nx - 0.5, ny - 0.5)
                let centerWeight = clamp(1.0 - centerDistance / 0.78, 0, 1)

                let borderPenalty: Float = (nx < 0.025 || nx > 0.975 || ny < 0.025 || ny > 0.975) ? 0.18 : 0
                var score = 0.42 * localContrast + 0.25 * tissueCue + 0.25 * depthCue + 0.08 * centerWeight - borderPenalty
                if !depthGrid.hasDepth[index] {
                    score *= 0.68
                }
                scores[index] = clamp(score, 0, 1)
            }
        }

        let sortedScores = scores.sorted()
        let adaptiveThreshold = max(0.32, percentile(sortedScores, 0.88))
        var mask = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            let score = scores[index]
            if score >= adaptiveThreshold {
                let normalized = clamp((score - adaptiveThreshold) / max(0.001, 1.0 - adaptiveThreshold), 0, 1)
                mask[index] = UInt8(clamp(90.0 + normalized * 165.0, 0, 255))
            }
        }

        mask = morphologyClose(mask, width: width, height: height, threshold: 76)
        return MaskGrid(width: width, height: height, values: mask)
    }

    private func combine(modelMask: MaskGrid, heuristicMask: MaskGrid) -> MaskGrid {
        guard modelMask.width == heuristicMask.width, modelMask.height == heuristicMask.height else {
            return modelMask
        }
        var values = modelMask.values
        for index in values.indices {
            let modelValue = Float(modelMask.values[index])
            let heuristicValue = Float(heuristicMask.values[index])
            let fused = max(modelValue * 0.78, modelValue * 0.58 + heuristicValue * 0.42)
            values[index] = UInt8(clamp(fused, 0, 255))
        }
        return MaskGrid(width: modelMask.width, height: modelMask.height, values: values)
    }

    private func applyTemporalSmoothing(to mask: MaskGrid) -> MaskGrid {
        guard let previousMask,
              previousMask.width == mask.width,
              previousMask.height == mask.height else {
            return mask
        }
        var values = mask.values
        for index in values.indices {
            let smoothed = Float(mask.values[index]) * 0.74 + Float(previousMask.values[index]) * 0.26
            values[index] = UInt8(clamp(smoothed, 0, 255))
        }
        return keepBestComponent(MaskGrid(width: mask.width, height: mask.height, values: values), preferredCenterBias: 0.12)
    }

    private func keepBestComponent(_ mask: MaskGrid, preferredCenterBias: Float) -> MaskGrid {
        let width = mask.width
        let height = mask.height
        let count = width * height
        var visited = [Bool](repeating: false, count: count)
        var bestPixels: [Int] = []
        var bestScore: Float = -.greatestFiniteMagnitude
        let minPixels = max(14, Int(Float(count) * 0.00035))
        let maxPixels = Int(Float(count) * 0.48)

        for start in 0..<count where !visited[start] && mask.values[start] > 76 {
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

                let neighbors = [
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1)
                ]
                for (nx, ny) in neighbors {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighborIndex = ny * width + nx
                    guard !visited[neighborIndex], mask.values[neighborIndex] > 76 else { continue }
                    visited[neighborIndex] = true
                    queue.append(neighborIndex)
                }
            }

            let pixelCount = pixels.count
            guard pixelCount >= minPixels, pixelCount <= maxPixels else { continue }

            let centroidX = sumX / Float(pixelCount) / Float(width)
            let centroidY = sumY / Float(pixelCount) / Float(height)
            let centerDistance = hypot(centroidX - 0.5, centroidY - 0.5)
            let probability = sumProbability / Float(max(1, pixelCount) * 255)
            let bboxRatio = Float((maxX - minX + 1) * (maxY - minY + 1)) / Float(count)
            let borderPenalty: Float = (minX <= 1 || minY <= 1 || maxX >= width - 2 || maxY >= height - 2) ? 0.28 : 0
            let score = probability * sqrt(Float(pixelCount)) + preferredCenterBias * (1 - centerDistance) - borderPenalty - max(0, bboxRatio - 0.38)

            if score > bestScore {
                bestScore = score
                bestPixels = pixels
            }
        }

        guard !bestPixels.isEmpty else { return mask }
        var values = [UInt8](repeating: 0, count: count)
        for index in bestPixels {
            values[index] = mask.values[index]
        }
        values = morphologyClose(values, width: width, height: height, threshold: 76)
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
        var validDepthPixels = 0
        var totalMaskPixels = 0

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
                }
            }
        }

        guard allCameraPoints.count >= 8 else { return nil }
        let edgePoints = edgeCameraPoints.count >= 8 ? edgeCameraPoints : allCameraPoints.map(\.point)
        guard let plane = fitPlane(to: edgePoints) else { return nil }

        var signedDepths: [(signed: Float, areaM2: Float, point: SIMD3<Float>, world: SIMD3<Float>)] = []
        signedDepths.reserveCapacity(allCameraPoints.count)
        for item in allCameraPoints {
            let signed = simd_dot(item.point - plane.origin, plane.normal)
            guard signed.isFinite else { continue }
            let world = worldPoint(fromCameraPoint: item.point, frame: frame)
            signedDepths.append((signed, item.areaM2, item.point, world))
        }

        let positive = signedDepths.map(\.signed).filter { $0 > 0.00035 }.sorted()
        let negative = signedDepths.map(\.signed).filter { $0 < -0.00035 }.map { -$0 }.sorted()
        let positiveDepth = percentile(positive, 0.88)
        let negativeDepth = percentile(negative, 0.88)
        let depressionSign: Float = positiveDepth >= negativeDepth ? 1 : -1

        var areaM2: Float = 0
        var volumeM3: Float = 0
        var maxDepthM: Float = 0
        var deepestWorldPoint: SIMD3<Float>?
        var inlierCount = 0

        for sample in signedDepths {
            areaM2 += sample.areaM2
            let depressionM = sample.signed * depressionSign
            guard depressionM.isFinite, depressionM > 0.00025, depressionM < 0.09 else { continue }
            let weightedDepth = min(depressionM, 0.09)
            volumeM3 += sample.areaM2 * weightedDepth
            inlierCount += 1
            if weightedDepth > maxDepthM {
                maxDepthM = weightedDepth
                deepestWorldPoint = sample.world
            }
        }

        let perimeterM = perimeter(points: boundaryWorldPoints)
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

    private func boundaryPolygon(from mask: MaskGrid, threshold: UInt8) -> [CGPoint] {
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

    private func nearestDepth(in depthGrid: DepthGrid, x: Int, y: Int) -> Float? {
        let index = y * depthGrid.width + x
        if depthGrid.hasDepth[index] { return depthGrid.depthM[index] }
        for radius in 1...4 {
            var sum: Float = 0
            var count: Float = 0
            for yy in max(0, y - radius)...min(depthGrid.height - 1, y + radius) {
                for xx in max(0, x - radius)...min(depthGrid.width - 1, x + radius) {
                    let neighbor = yy * depthGrid.width + xx
                    guard depthGrid.hasDepth[neighbor] else { continue }
                    sum += depthGrid.depthM[neighbor]
                    count += 1
                }
            }
            if count > 0 { return sum / count }
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

    private func computeSkinITA(mask: MaskGrid, colorGrid: ColorGrid, boundingRect: CGRect) -> Float {
        guard boundingRect != .zero else { return 0 }
        let width = mask.width
        let height = mask.height
        let insetX = max(4, Int(CGFloat(width) * boundingRect.width * 0.34))
        let insetY = max(4, Int(CGFloat(height) * boundingRect.height * 0.34))
        let minX = max(0, Int(boundingRect.minX * CGFloat(width)) - insetX)
        let maxX = min(width - 1, Int(boundingRect.maxX * CGFloat(width)) + insetX)
        let minY = max(0, Int(boundingRect.minY * CGFloat(height)) - insetY)
        let maxY = min(height - 1, Int(boundingRect.maxY * CGFloat(height)) + insetY)

        var lSum: Float = 0
        var bSum: Float = 0
        var count: Float = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let index = y * width + x
                guard mask.values[index] <= segmentationThreshold else { continue }
                lSum += colorGrid.lStar[index]
                bSum += colorGrid.bStar[index]
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let meanL = lSum / count
        let meanB = bSum / count
        return atan2(meanL - 50.0, max(meanB, 0.001)) * 180.0 / .pi
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

        let maskRatio = mask.foregroundRatio
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

    private func makeMaskPixelBuffer(from mask: MaskGrid) -> CVPixelBuffer? {
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
                row.storeBytes(of: mask.values[y * mask.width + x], toByteOffset: x, as: UInt8.self)
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
