Pod::Spec.new do |s|
  s.name = 'qr_image_decoder'
  s.version = '1.0.0'
  s.summary = 'Local bounded image decoding for QR scanning.'
  s.homepage = 'https://99chat.vip'
  s.license = { :type => 'Proprietary' }
  s.author = { '99Chat' => 'https://99chat.vip' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.frameworks = 'ImageIO', 'CoreGraphics'
end
