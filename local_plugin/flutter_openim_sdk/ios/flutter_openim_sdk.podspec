#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_openim_sdk.podspec` to validate before publishing.
#
require 'open3'
core_root = File.expand_path('../../../native_sdk/patch15', File.realpath(__dir__))
output, status = Open3.capture2e(ENV.fetch('CORE_PYTHON', 'python3'), File.join(core_root, 'prepare_source.py'), '--check-artifact', 'ios')
raise "OpenIM Core verification failed: #{output}" unless status.success?

Pod::Spec.new do |s|
  s.name             = 'flutter_openim_sdk'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter project.'
  s.description      = <<-DESC
A new Flutter project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # patch.15 + the same recovery patch as Android; build via native_sdk/patch15/build-ios.sh.
  s.vendored_frameworks = 'Frameworks/OpenIMCore.xcframework'
  # Flutter can reuse Pods, and Xcode can build without evaluating this spec.
  # No output files: Xcode runs this guard on every build, before compilation.
  s.script_phase = {
    :name => 'Verify shared OpenIM Core',
    :execution_position => :before_compile,
    :shell_path => '/bin/sh',
    :script => <<-'SH'
set -eu
plugin_root="$(cd "$PODS_TARGET_SRCROOT" && pwd -P)"
"${CORE_PYTHON:-python3}" "$plugin_root/../../../native_sdk/patch15/prepare_source.py" --check-artifact ios
SH
  }
  s.static_framework = true
  s.library = 'resolv'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO' }
  s.swift_version = '5.0'

  s.resource_bundles = {'flutter_openim_sdk_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
