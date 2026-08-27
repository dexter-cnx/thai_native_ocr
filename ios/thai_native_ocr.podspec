Pod::Spec.new do |s|
  s.name             = 'thai_native_ocr'
  s.version          = '0.1.0'
  s.summary          = 'Hybrid native OCR for Flutter.'
  s.description      = <<-DESC
Apple Vision OCR on iOS and Tesseract OCR on Android with Thai auto-detection.
                       DESC
  s.homepage         = 'https://github.com/dexter-cnx/thai_native_ocr'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dexter CNXcoder' => 'dexter-cnx@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.frameworks = 'Vision', 'UIKit'

  # Intentionally no Tesseract pod and no tessdata resources on iOS.
  # Do not add s.resources for traineddata: Vision is the complete iOS OCR path.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
