import CoreImage
import Flutter
import UIKit
import Vision

public class ThaiNativeOcrPlugin: NSObject, FlutterPlugin {
  private let ciContext = CIContext(options: nil)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "thai_native_ocr", binaryMessenger: registrar.messenger())
    let instance = ThaiNativeOcrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "OCR arguments are required.", details: nil))
      return
    }

    let imagePath = arguments["imagePath"] as? String
    let imageBytes = (arguments["imageBytes"] as? FlutterStandardTypedData)?.data
    guard (imagePath?.isEmpty == false) || (imageBytes?.isEmpty == false) else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "imagePath or imageBytes is required.",
        details: nil
      ))
      return
    }

    let autoDetectThai = arguments["autoDetectThai"] as? Bool ?? true
    let forceLanguage = arguments["forceLanguage"] as? String
    let preprocess = arguments["preprocess"] as? Bool ?? false

    if let forceLanguage = forceLanguage, !["th", "en", "mixed"].contains(forceLanguage) {
      result(FlutterError(
        code: "INVALID_FORCE_LANGUAGE",
        message: "forceLanguage must be th, en, or mixed.",
        details: nil
      ))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let image = try self.loadImage(path: imagePath, bytes: imageBytes)
        let output = try self.recognize(
          image: image,
          autoDetectThai: autoDetectThai,
          forceLanguage: forceLanguage,
          preprocess: preprocess
        )

        DispatchQueue.main.async {
          result([
            "text": output.text,
            "containsThai": output.containsThai,
            "detectedLanguage": output.detectedLanguage,
            "confidence": output.confidence,
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "OCR_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private func recognize(
    image: UIImage,
    autoDetectThai: Bool,
    forceLanguage: String?,
    preprocess: Bool
  ) throws -> (text: String, containsThai: Bool, detectedLanguage: String, confidence: Float) {
    var stage1ContainsThai = false
    let stage2Languages: [String]

    if let forceLanguage = forceLanguage {
      switch forceLanguage {
      case "en":
        stage2Languages = ["en-US"]
      case "th", "mixed":
        stage2Languages = ["th-TH", "en-US"]
      default:
        stage2Languages = ["th-TH", "en-US"]
      }
    } else if !autoDetectThai {
      stage2Languages = ["th-TH", "en-US"]
    } else {
      let stage1 = try runVision(
        image: image,
        languages: [],
        level: .fast,
        usesLanguageCorrection: false,
        automaticallyDetectsLanguage: true
      )
      stage1ContainsThai = containsThai(stage1.text)
      stage2Languages = stage1ContainsThai ? ["th-TH", "en-US"] : ["en-US"]
    }

    let accurateImage = preprocess ? try preprocessImage(image) : image
    let stage2 = try runVision(
      image: accurateImage,
      languages: stage2Languages,
      level: .accurate,
      usesLanguageCorrection: stage2Languages.contains("th-TH"),
      automaticallyDetectsLanguage: false
    )

    let finalContainsThai = stage1ContainsThai || containsThai(stage2.text)
    let detectedLanguage = detectLanguage(in: stage2.text, containsThai: finalContainsThai)

    return (stage2.text, finalContainsThai, detectedLanguage, stage2.confidence)
  }

  private func runVision(
    image: UIImage,
    languages: [String],
    level: VNRequestTextRecognitionLevel,
    usesLanguageCorrection: Bool,
    automaticallyDetectsLanguage: Bool
  ) throws -> (text: String, confidence: Float) {
    guard let cgImage = image.cgImage else {
      throw OcrError.invalidImage
    }

    var requestError: Error?
    var lines: [(text: String, confidence: Float)] = []

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        requestError = error
        return
      }

      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      lines = observations.compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else {
          return nil
        }
        return (candidate.string, candidate.confidence)
      }
    }

    request.recognitionLevel = level
    request.usesLanguageCorrection = usesLanguageCorrection
    request.recognitionLanguages = languages

    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = languages.isEmpty && automaticallyDetectsLanguage
    }

    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: cgImageOrientation(from: image.imageOrientation),
      options: [:]
    )
    try handler.perform([request])

    if let requestError = requestError {
      throw requestError
    }

    let text = lines.map(\.text).joined(separator: "\n")
    let confidence: Float
    if lines.isEmpty {
      confidence = 0
    } else {
      confidence = lines.reduce(0) { $0 + $1.confidence } / Float(lines.count)
    }

    return (text, min(max(confidence, 0), 1))
  }

  private func preprocessImage(_ image: UIImage) throws -> UIImage {
    guard let ciImage = CIImage(image: image),
          let filter = CIFilter(name: "CIColorControls") else {
      throw OcrError.invalidImage
    }

    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(0.0, forKey: kCIInputSaturationKey)
    filter.setValue(1.35, forKey: kCIInputContrastKey)
    filter.setValue(0.04, forKey: kCIInputBrightnessKey)

    guard let output = filter.outputImage,
          let cgImage = ciContext.createCGImage(output, from: output.extent) else {
      throw OcrError.invalidImage
    }

    return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }

  private func containsThai(_ text: String) -> Bool {
    return text.unicodeScalars.contains { scalar in
      scalar.value >= 0x0E00 && scalar.value <= 0x0E7F
    }
  }

  private func detectLanguage(in text: String, containsThai: Bool) -> String {
    let containsLatin = text.range(of: "[A-Za-z]", options: .regularExpression) != nil
    if containsThai && containsLatin {
      return "mixed"
    }
    if containsThai {
      return "th"
    }
    return "en"
  }

  private func loadImage(path: String?, bytes: Data?) throws -> UIImage {
    if let bytes = bytes, !bytes.isEmpty, let image = UIImage(data: bytes) {
      return image
    }

    guard let path = path, !path.isEmpty else {
      throw OcrError.imageNotFound
    }

    let resolvedPath: String
    if let url = URL(string: path), url.isFileURL {
      resolvedPath = url.path
    } else {
      resolvedPath = path
    }

    if let image = UIImage(contentsOfFile: resolvedPath) {
      return image
    }

    let sourceURL = URL(fileURLWithPath: resolvedPath)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("thai_native_ocr_\(UUID().uuidString)")
      .appendingPathExtension(sourceURL.pathExtension)

    do {
      try FileManager.default.copyItem(at: sourceURL, to: tempURL)
      defer { try? FileManager.default.removeItem(at: tempURL) }
      if let image = UIImage(contentsOfFile: tempURL.path) {
        return image
      }
    } catch {
      // Preserve a single public error surface below.
    }

    throw OcrError.imageNotFound
  }

  private func cgImageOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

private enum OcrError: LocalizedError {
  case imageNotFound
  case invalidImage

  var errorDescription: String? {
    switch self {
    case .imageNotFound:
      return "Unable to load the image from imagePath or imageBytes."
    case .invalidImage:
      return "Unable to prepare the image for Vision OCR."
    }
  }
}
