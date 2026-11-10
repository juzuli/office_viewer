Pod::Spec.new do |s|
  s.name             = 'office_viewer_engine_convert'
  s.version          = '0.1.0'
  s.summary          = 'FFI plugin for office_viewer_engine_convert (Office Oxide)'
  s.description      = <<-DESC
    Vendors Office Oxide as a dynamic XCFramework so Dart FFI can open
    OfficeOxide.framework/OfficeOxide on iOS (legacy DOC/XLS/PPT convert).
  DESC
  s.homepage         = 'https://github.com/juzuli/office_viewer'
  s.license          = { :type => 'MIT' }
  s.author           = { 'office_viewer' => 'https://github.com/juzuli/office_viewer' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'

  # Built by tool/build_ios_oxide.sh (device arm64 + sim arm64 dynamic frameworks).
  s.vendored_frameworks = 'Frameworks/OfficeOxide.xcframework'
  s.preserve_paths = 'Frameworks/OfficeOxide.xcframework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
