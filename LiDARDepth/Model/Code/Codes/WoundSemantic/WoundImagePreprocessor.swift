import CoreGraphics
import CoreVideo
import UIKit

enum WoundImagePreprocessorError: Error {
    case couldNotNormalizeOrientation
    case couldNotCreatePixelBuffer(OSStatus)
    case couldNotCreateGraphicsContext
}

enum WoundImagePreprocessor {
    static func makeModelPixelBuffer(from image: UIImage) throws -> CVPixelBuffer {
        guard image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw WoundImagePreprocessorError.couldNotNormalizeOrientation
        }

        let size = WoundModelContract.inputSize
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
            throw WoundImagePreprocessorError.couldNotCreatePixelBuffer(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            throw WoundImagePreprocessorError.couldNotCreateGraphicsContext
        }

        let fill = WoundModelContract.neutralFillRGB
        context.setFillColor(
            red: CGFloat(fill.red) / 255,
            green: CGFloat(fill.green) / 255,
            blue: CGFloat(fill.blue) / 255,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .medium

        let scale = min(
            CGFloat(size) / image.size.width,
            CGFloat(size) / image.size.height
        )
        let width = image.size.width * scale
        let height = image.size.height * scale
        let destination = CGRect(
            x: (CGFloat(size) - width) / 2,
            y: (CGFloat(size) - height) / 2,
            width: width,
            height: height
        )
        // UIKit applies UIImage orientation while drawing directly into the small model buffer.
        // Avoid rendering a second full-resolution camera image just to rotate it.
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: destination)
        UIGraphicsPopContext()
        return pixelBuffer
    }

}
