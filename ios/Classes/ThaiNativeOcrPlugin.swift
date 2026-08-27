import Flutter
import UIKit
import Vision

public class ThaiNativeOcrPlugin: NSObject, FlutterPlugin {
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

    guard
      let arguments = call.arguments as? [String: Any],
      let imagePath = arguments["imagePath"] as? String,
      !imagePath.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "imagePath is required.", details: nil))
      return
    }

    let autoDetectThai = arguments["autoDetectThai"] as? Bool ?? true
    let forceLanguage = arguments["forceLanguage"] as? String

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
        let image = try self.loadImage(path: imagePath)
        let output = try self.recognize(
          image: image,
          autoDetectThai: autoDetectThai,
          forceLanguage: forceLanguage
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
    forceLanguage: String?
  ) throws -> (text: String, containsThai: Bool, detectedLanguage: String, confidence: Float) {
    var stage1ContainsThai = false
    let stage2Languages: [String]

    if let forceLanguage = forceLanguage {
      switch forceLanguage {
      case "en":
        stage2Languages = ["en-US"]
      case "th", "mixed":
        // Thai recognition always keeps English enabled. `th` is retained as
        // a backward-compatible alias for the bilingual strategy.
        stage2Languages = ["th-TH", "en-US"]
      default:
        stage2Languages = ["th-TH", "en-US"]
      }
    } else if !autoDetectThai {
      // Explicit bypass: skip Stage 1 and run the bilingual accurate model.
      stage2Languages = ["th-TH", "en-US"]
    } else {
      // Stage 1: lightweight detector. No explicit languages means Vision may
      // automatically detect the language. The OCR text is used only to decide
      // which language set the accurate pass should use.
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

    // Stage 2 has only two execution modes: bilingual Thai+English or English.
    let stage2 = try runVision(
      image: image,
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
    level: VNRequestTextRecognitionLevel
  ) throws -> (text: String, confidence: Float) {
    try runVision(
      image: image,
      languages: languages,
      level: level,
      usesLanguageCorrection: level == .accurate,
      automaticallyDetectsLanguage: languages.isEmpty
    )
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

  private func containsThai(_ text: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: "[\\u0E00-\\u0E7F]") else {
      return false
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, options: [], range: range) != nil
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

  private func loadImage(path: String) throws -> UIImage {
    let resolvedPath: String
    if let url = URL(string: path), url.isFileURL {
      resolvedPath = url.path
    } else {
      resolvedPath = path
    }

    if let image = UIImage(contentsOfFile: resolvedPath) {
      return image
    }

    // Some Flutter image providers return a file URL outside the plugin's
    // preferred temporary location. Copying is a fallback only; Vision itself
    // never depends on a Tesseract-style bundle/resource path.
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
      return "Unable to load the image from imagePath."
    case .invalidImage:
      return "Unable to create a CGImage for Vision OCR."
    }
  }
}
