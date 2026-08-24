#
# QuickJS Flutter FFI plugin (macOS)
#
Pod::Spec.new do |s|
  s.name             = 'lemon_js'
  s.version          = '0.0.1'
  s.summary          = 'QuickJS JavaScript engine for Flutter'
  s.description      = <<-DESC
Embeds QuickJS (https://github.com/quickjs/quickjs) for JavaScript evaluation on macOS.
                       DESC
  s.homepage         = 'https://github.com/quickjs/quickjs'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'quickjs' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'

  s.source_files = [
    'lemon_js/Sources/lemon_js/**/*.swift',
    '../third_party/quickjs/dtoa.c',
    '../third_party/quickjs/libregexp.c',
    '../third_party/quickjs/libunicode.c',
    '../third_party/quickjs/quickjs.c',
    '../third_party/quickjs/quickjs-libc.c',
    '../native/quickjs_bridge.c',
    '../native/quickjs_bridge.h',
  ]
  s.public_header_files = '../native/quickjs_bridge.h'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../third_party/quickjs" "$(PODS_TARGET_SRCROOT)/../native"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'QUICKJS_BUILD=1 QUICKJS_BRIDGE_BUILD=1',
  }
  s.swift_version = '5.0'
end
