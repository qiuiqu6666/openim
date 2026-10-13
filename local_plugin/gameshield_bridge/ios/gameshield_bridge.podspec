require 'json'
require 'digest'

Pod::Spec.new do |s|
  s.name = 'gameshield_bridge'
  s.version = '0.1.0'
  s.summary = 'Optional GameShield forwarding bridge for OpenIM.'
  s.description = 'Engine-owned GameShield client with serialized lifecycle operations.'
  s.homepage = 'https://github.com/openimsdk/open-im-sdk-flutter'
  s.license = { :type => 'MIT' }
  s.author = 'OpenIM app maintainers'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.static_framework = true
  s.frameworks = 'Foundation', 'Network', 'UIKit'

  vendor = File.expand_path('../vendor/ios', __dir__)
  framework = File.join(vendor, 'GameShieldSDK.xcframework')
  if File.directory?(framework)
    receipt_path = File.join(vendor, 'compatibility.json')
    raise 'GameShield requires a compatibility receipt from tool/gameshield/check_sdk.py.' unless File.file?(receipt_path)
    receipt = JSON.parse(File.read(receipt_path))
    raise 'GameShield SDK did not pass compatibility checks.' unless receipt['schema'] == 1 && receipt['platform'] == 'ios' && receipt['compatible'] == true
    files = receipt.fetch('files')
    raise 'GameShield compatibility receipt is empty.' if files.empty?
    files.each do |relative, digest|
      path = File.expand_path(relative, vendor)
      raise 'Invalid GameShield SDK path.' unless path.start_with?(vendor + File::SEPARATOR)
      raise 'GameShield SDK changed. Recheck and stage the SDK.' unless File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
    end
    s.vendored_frameworks = '../vendor/ios/GameShieldSDK.xcframework'
  end
end
