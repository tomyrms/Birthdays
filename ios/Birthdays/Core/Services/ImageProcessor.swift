import CoreImage
import ImageIO
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

struct MemoryLensArtwork: @unchecked Sendable {
    let image: UIImage
    let accentColor: UIColor
}

actor MemoryLensArtworkCache {
    static let shared = MemoryLensArtworkCache()

    private struct Key: Hashable {
        let photoHash: Int
        let aspectRatioBits: UInt64
    }

    private var values: [Key: MemoryLensArtwork] = [:]
    private var insertionOrder: [Key] = []
    private let capacity = 6

    func artwork(from data: Data, aspectRatio: CGFloat = 0.96) async -> MemoryLensArtwork? {
        let key = Key(
            photoHash: data.hashValue,
            aspectRatioBits: Double(aspectRatio).bitPattern
        )
        if let cached = values[key] { return cached }

        // Cette image alimente directement la carte visible à l'écran : à
        // `.utility`, elle peut se faire distancer par le reste du travail de
        // démarrage et ne jamais rattraper son retard tant que l'app tourne.
        let generated = await Task.detached(priority: .userInitiated) {
            ImageProcessor.memoryLensArtwork(from: data, aspectRatio: aspectRatio)
        }.value
        guard let generated else { return nil }

        if values.count >= capacity, let oldest = insertionOrder.first {
            values.removeValue(forKey: oldest)
            insertionOrder.removeFirst()
        }
        values[key] = generated
        insertionOrder.append(key)
        return generated
    }
}

enum ImageProcessor {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Décode directement à la taille voulue. Passer par `UIImage(data:)`
    /// matérialisait d'abord l'image en pleine résolution : une photo de
    /// 12 Mpx occupe environ 48 Mo en mémoire avant même d'être réduite.
    static func thumbnailData(from data: Data, maximumDimension: CGFloat = 640) -> Data? {
        if let reduced = downsampled(data, maxPixel: maximumDimension) { return reduced }

        // Repli sur l'ancien chemin si le format échappe à ImageIO.
        guard let source = UIImage(data: data) else { return nil }
        let image = normalized(source)
        let scale = min(maximumDimension / max(image.size.width, image.size.height), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.78)
    }

    private static func downsampled(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.78)
    }

    static func memoryLensArtwork(from data: Data, aspectRatio: CGFloat = 0.96) -> MemoryLensArtwork? {
        guard let source = UIImage(data: data) else { return nil }
        let image = normalized(source)
        let focus = visualFocus(in: image)
        guard let cropped = croppedImage(image, aspectRatio: aspectRatio, focus: focus) else { return nil }

        return MemoryLensArtwork(
            image: cropped,
            accentColor: accentColor(in: cropped)
        )
    }

    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func visualFocus(in image: UIImage) -> CGPoint {
        guard let cgImage = image.cgImage else { return CGPoint(x: 0.5, y: 0.42) }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let faceRequest = VNDetectFaceRectanglesRequest()

        if (try? handler.perform([faceRequest])) != nil,
           let faces = faceRequest.results,
           !faces.isEmpty {
            let union = faces.dropFirst().reduce(faces[0].boundingBox) { partial, face in
                partial.union(face.boundingBox)
            }
            // Vision starts at the bottom-left; UIKit starts at the top-left.
            return CGPoint(x: union.midX, y: 1 - union.midY + union.height * 0.16)
        }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        if (try? handler.perform([saliencyRequest])) != nil,
           let observation = saliencyRequest.results?.first as? VNSaliencyImageObservation,
           let regions = observation.salientObjects,
           !regions.isEmpty {
            let union = regions.dropFirst().reduce(regions[0].boundingBox) { partial, region in
                partial.union(region.boundingBox)
            }
            return CGPoint(x: union.midX, y: 1 - union.midY)
        }

        return CGPoint(x: 0.5, y: 0.42)
    }

    private static func croppedImage(
        _ image: UIImage,
        aspectRatio: CGFloat,
        focus: CGPoint
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let sourceRatio = width / height

        let cropSize: CGSize
        if sourceRatio > aspectRatio {
            cropSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            cropSize = CGSize(width: width, height: width / aspectRatio)
        }

        let focusedX = min(max(focus.x, 0), 1) * width
        let focusedY = min(max(focus.y, 0), 1) * height
        let originX = min(max(focusedX - cropSize.width / 2, 0), width - cropSize.width)
        let originY = min(max(focusedY - cropSize.height * 0.38, 0), height - cropSize.height)
        let cropRect = CGRect(origin: CGPoint(x: originX, y: originY), size: cropSize).integral

        guard let result = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    private static func accentColor(in image: UIImage) -> UIColor {
        guard let input = CIImage(image: image) else { return UIColor(red: 0.46, green: 0.35, blue: 1, alpha: 1) }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent

        var pixels = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let output = filter.outputImage else {
            return UIColor(red: 0.46, green: 0.35, blue: 1, alpha: 1)
        }
        ciContext.render(
            output,
            toBitmap: &pixels,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        let sampled = UIColor(
            red: CGFloat(pixels[0]) / 255,
            green: CGFloat(pixels[1]) / 255,
            blue: CGFloat(pixels[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        sampled.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return UIColor(
            hue: hue,
            saturation: min(max(saturation * 1.35, 0.42), 0.78),
            brightness: min(max(brightness, 0.52), 0.78),
            alpha: 1
        )
    }
}
