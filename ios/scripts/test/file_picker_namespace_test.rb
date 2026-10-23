require 'minitest/autorun'
require_relative '../file_picker_namespace'

class FilePickerNamespaceTest < Minitest::Test
  Config = Struct.new(:build_settings)
  Target = Struct.new(:name, :build_configurations)

  def test_renames_only_file_picker_and_preserves_feature_defines
    config = Config.new({ 'GCC_PREPROCESSOR_DEFINITIONS' => ['$(inherited)', 'PICKER_DOCUMENT=1'] })
    target = Target.new('file_picker', [config])
    2.times { IOSFilePickerNamespace.apply!(target) }
    assert_equal ['$(inherited)', 'PICKER_DOCUMENT=1', 'FileUtils=Chat99FilePickerFileUtils'],
                 config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']
    unrelated = Target.new('Runner', [Config.new({})])
    IOSFilePickerNamespace.apply!(unrelated)
    assert_empty unrelated.build_configurations.first.build_settings
  end

  def test_supports_nil_and_string_settings_without_erasing_other_flags
    [nil, 'PICKER_AUDIO=1 PICKER_MEDIA=1'].each do |value|
      config = Config.new({ 'GCC_PREPROCESSOR_DEFINITIONS' => value })
      IOSFilePickerNamespace.apply!(Target.new('file_picker', [config]))
      result = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']
      assert_includes result, '$(inherited)'
      assert_includes result, IOSFilePickerNamespace::DEFINITION
      assert_includes result, 'PICKER_AUDIO=1' if value
    end
  end
end
