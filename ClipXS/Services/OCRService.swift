import Foundation
import ImageIO
import Vision

/// On-device text recognition for image entries (Vision framework; no data
/// leaves the machine). Results are stored alongside the entry so search can
/// match text inside screenshots.
enum OCRService {
    private static let queue = DispatchQueue(label: "com.clipxs.ocr", qos: .utility)

    /// Calls `completion` on an arbitrary queue with the recognized text, or
    /// nil when nothing was recognized or recognition failed.
    static func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                completion(nil)
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    NSLog("ClipXS: OCR failed: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                completion(text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ja-JP", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("ClipXS: OCR handler failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}
