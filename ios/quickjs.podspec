#
# QuickJS Flutter FFI plugin (iOS)
#
Pod::Spec.new do |s|
  s.name             = 'quickjs'
  s.version          = '0.0.1'
  s.summary          = 'QuickJS JavaScript engine for Flutter'
  s.description      = <<-DESC
Embeds QuickJS (https://github.com/quickjs/quickjs) for JavaScript evaluation on iOS.
                       DESC
  s.homepage         = 'https://github.com/quickjs/quickjs'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'quickjs' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'

  quickjs_dir = File.expand_path('../third_party/quickjs', __dir__)
  bridge_dir = File.expand_path('../native', __dir__)

  s.source_files = [
    'quickjs/Sources/quickjs/**/*.swift',
    File.join(quickjs_dir, 'dtoa.c'),
    File.join(quickjs_dir, 'libregexp.c'),
    File.join(quickjs_dir, 'libunicode.c'),
    File.join(quickjs_dir, 'quickjs.c'),
    File.join(quickjs_dir, 'quickjs-libc.c'),
    File.join(bridge_dir, 'quickjs_bridge.c'),
  ]
  s.public_header_files = File.join(bridge_dir, 'quickjs_bridge.h')
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => "\"#{quickjs_dir}\" \"#{bridge_dir}\"",
    'GCC_PREPROCESSOR_DEFINITIONS' => 'QUICKJS_BUILD=1 QUICKJS_BRIDGE_BUILD=1',
  }
  s.swift_version = '5.0'
end
