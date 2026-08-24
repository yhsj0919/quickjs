Pod::Spec.new do |s|
  s.name             = 'lemon_js'
  s.version          = '0.2.1'
  s.summary          = 'QuickJS JavaScript engine for Flutter'
  s.description      = <<-DESC
Embeds QuickJS for JavaScript evaluation on iOS and macOS.
                       DESC
  s.homepage         = 'https://github.com/yhsj0919/quickjs'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'lemon_js' => 'dev@example.com' }
  s.source           = { :git => 'https://github.com/yhsj0919/quickjs.git', :tag => s.version.to_s }

  s.source_files = [
    'lemon_js/Sources/lemon_js/**/*.swift',
    'lemon_js/Sources/lemon_js_native/**/*.{c,h}',
  ]
  s.public_header_files = 'lemon_js/Sources/lemon_js_native/include/**/*.h'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '_GNU_SOURCE=1 QUICKJS_BUILD=1 QUICKJS_BRIDGE_BUILD=1',
  }
  s.swift_version = '5.0'
  s.resource_bundles = {
    'lemon_js_privacy' => ['lemon_js/Sources/lemon_js/PrivacyInfo.xcprivacy'],
  }
end
