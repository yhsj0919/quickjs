#
# QuickJS Flutter FFI plugin (iOS)
#
Pod::Spec.new do |s|
  s.name             = 'lemon_js'
  s.version          = '0.0.1'
  s.summary          = 'QuickJS JavaScript engine for Flutter'
  s.description      = <<-DESC
Embeds QuickJS (https://github.com/quickjs/quickjs) for JavaScript evaluation on iOS.
                       DESC
  s.homepage         = 'https://github.com/quickjs/quickjs'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'quickjs' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'

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
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../third_party/quickjs" "$(PODS_TARGET_SRCROOT)/../native"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'QUICKJS_BUILD=1 QUICKJS_BRIDGE_BUILD=1',
  }
  s.swift_version = '5.0'
end
