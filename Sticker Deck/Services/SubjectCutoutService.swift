import UIKit
import Vision
import CoreImage

protocol SubjectCutting: Sendable {
    nonisolated func cutout(from image: UIImage) async throws -> UIImage
}

enum SubjectCutoutError: LocalizedError {
    case noSubject, unavailable
    var errorDescription: String? {
        switch self {
        case .noSubject: "No clear subject was found. Try another photo, or keep the original."
        case .unavailable: "Subject cutout isn’t available for this image or device. Retry, or keep the original photo."
        }
    }
}

struct AppleSubjectCutoutService: SubjectCutting {
    nonisolated func cutout(from image: UIImage) async throws -> UIImage {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let cgImage = image.cgImage else { throw SubjectCutoutError.unavailable }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            let request = VNGenerateForegroundInstanceMaskRequest()
            do {
                try handler.perform([request])
                try Task.checkCancellation()
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                    throw SubjectCutoutError.noSubject
                }
                // Preserve every detected foreground subject. Cropping removes unused transparent margins.
                let buffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
                let cutout = CIImage(cvPixelBuffer: buffer)
                guard let output = CIContext().createCGImage(cutout, from: cutout.extent) else {
                    throw SubjectCutoutError.unavailable
                }
                try Task.checkCancellation()
                return UIImage(cgImage: output)
            } catch is CancellationError { throw CancellationError() }
            catch let error as SubjectCutoutError { throw error }
            catch { throw SubjectCutoutError.unavailable }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
