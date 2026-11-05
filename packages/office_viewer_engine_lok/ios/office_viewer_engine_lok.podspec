#
# iOS plugin for office_viewer_engine_lok — links a self-built CPiOS static
# engine when LOK_HOME_IOS is populated (tool/install_lok_home_ios.sh).
#
Pod::Spec.new do |s|
  s.name             = 'office_viewer_engine_lok'
  s.version          = '0.0.1'
  s.summary          = 'LOK tile engine for Leafpane office_viewer'
  s.description      = <<-DESC
Android: JNI + shared libs. iOS: static LOK archives + native bridge.
                       DESC
  s.homepage         = 'https://github.com/example/office_viewer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Leafpane' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m,mm,cpp,c}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'

  lok = ENV['LOK_HOME_IOS'] || File.expand_path(File.join(__dir__, '..', 'third_party', 'lok_ios'))
  lo_engine = ENV['LO_IOS_ENGINE']
  if lo_engine.nil? || lo_engine.empty?
    cand = [
      File.expand_path('~/lo-ios-build/lok-online/engine'),
      File.expand_path('~/lo-ios-build/collabora-office/engine'),
    ].find { |p| File.directory?(p) }
    lo_engine = cand || File.expand_path('~/lo-ios-build/lok-online/engine')
  end
  list = File.join(lok, 'ios-all-static-libs.list')
  resources = File.join(lok, 'resources')
  # Example/dev only: OFFICE_VIEWER_LINK_LOK_IOS=0 skips the 375-archive link.
  # Preference is persisted in the host app's ios/.lok_link_enabled so a later
  # `flutter run` (which re-runs pod install without the ENV) does not flip it.
  # Package consumers are unaffected unless they set this themselves — default ON.
  # Prefer the host Podfile directory; only fall back to this package's example/.
  # Dir.pwd is unreliable while CocoaPods evaluates path podspecs — use
  # installation_root (directory that contains the host Podfile).
  install_root = begin
                   Pod::Config.instance.installation_root.to_s
                 rescue StandardError
                   Dir.pwd
                 end
  host_pref = File.expand_path(File.join(install_root, '.lok_link_enabled'))
  example_pref = File.expand_path(File.join(__dir__, '..', '..', '..', 'example', 'ios', '.lok_link_enabled'))
  pref_file = if File.file?(host_pref)
                host_pref
              elsif File.file?(example_pref)
                example_pref
              end
  link_requested = if ENV.key?('OFFICE_VIEWER_LINK_LOK_IOS')
                     ENV['OFFICE_VIEWER_LINK_LOK_IOS'] != '0'
                   elsif pref_file
                     File.read(pref_file).strip != '0'
                   else
                     true
                   end
  # Headers live in the self-built LO engine tree; without them the link is unusable.
  engine_headers_ok = File.directory?(File.join(lo_engine, 'config_host')) ||
                      File.file?(File.join(lo_engine, 'config_host', 'config_crypto.h'))
  lok_ready = link_requested &&
              engine_headers_ok &&
              File.directory?(lok) && File.file?(list) && File.directory?(resources)
  Pod::UI.puts "office_viewer_engine_lok: LOK link #{lok_ready ? 'ON' : 'OFF (fast stub)'}"

  # Always exclude simulator for the LOK-linked configuration (device arm64 only).
  base_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) IOS=1 DISABLE_DYNLOADING=1',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64 i386 x86_64',
  }

  if lok_ready
    header_paths = [
      lok,
      File.join(lo_engine, 'include'),
      File.join(lo_engine, 'config_host'),
      File.join(lo_engine, 'workdir', 'CustomTarget', 'ios'),
      File.join(lo_engine, 'workdir', 'UnpackedTarball', 'boost'),
      File.join(lo_engine, 'workdir', 'UnoApiHeadersTarget', 'udkapi', 'comprehensive'),
      File.join(lo_engine, 'workdir', 'UnoApiHeadersTarget', 'offapi', 'comprehensive'),
    ].select { |p| File.directory?(p) || File.file?(p) }.join(' ')

    frameworks = %w[
      UIKit Foundation CoreGraphics CoreText CoreFoundation
      Security SystemConfiguration ImageIO QuartzCore
      MobileCoreServices CoreServices UniformTypeIdentifiers
      AudioToolbox AVFoundation CFNetwork Metal
    ].map { |f| "-framework #{f}" }.join(' ')

    # System libs: zlib/iconv match upstream ios/UnitTest; sqlite3 for NSS softokn.
    # Final link is the Runner app — put everything on user_target_xcconfig.
    sys_libs = '-lc++ -lz -liconv -lsqlite3'
    ld_flags = "$(inherited) -filelist #{list} #{sys_libs} -ObjC #{frameworks}"

    s.pod_target_xcconfig = base_xcconfig.merge({
      'HEADER_SEARCH_PATHS' => "$(inherited) #{header_paths}",
      'OTHER_LDFLAGS[sdk=iphoneos*]' => ld_flags,
      'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -x objective-c++',
    })
    s.user_target_xcconfig = {
      'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64 i386 x86_64',
      'OTHER_LDFLAGS[sdk=iphoneos*]' => ld_flags,
    }

    # Resources are copied into Runner.app root by the host Podfile
    # (iOS LOK $APP_DATA_DIR == main bundle). Keep a local tree for that copy.
    pod_resources = File.join(__dir__, 'LokIosResources')
    unless File.directory?(pod_resources) && !Dir.empty?(pod_resources)
      raise "Missing ios/LokIosResources — run tool/install_lok_home_ios.sh"
    end
    s.preserve_paths = ['LokIosResources']
  else
    # Stub-only build (no LOK_HOME_IOS yet). Init returns 0 until
    # tool/install_lok_home_ios.sh populates third_party/lok_ios.
    s.pod_target_xcconfig = base_xcconfig
    s.exclude_files = [
      'Classes/LokIosBridge.mm',
      'Classes/LokNativeCode.mm',
    ]
  end

  if lok_ready
    s.exclude_files = ['Classes/LokIosBridgeStub.mm']
  end
end
