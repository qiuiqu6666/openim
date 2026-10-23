require 'shellwords'

# file_picker 10.3.3 exports FileUtils, which collides with iOS OSAnalytics.
# Rename this pod's Objective-C helper and all its internal references at
# compilation. Never edit the shared pub cache or define this macro globally.
module IOSFilePickerNamespace
  DEFINITION = 'FileUtils=Chat99FilePickerFileUtils'.freeze

  def self.apply!(target)
    return unless target.name == 'file_picker'

    target.build_configurations.each do |config|
      original = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']
      definitions = original.is_a?(String) ? Shellwords.split(original) : Array(original).dup
      definitions.unshift('$(inherited)') unless definitions.include?('$(inherited)')
      definitions << DEFINITION unless definitions.include?(DEFINITION)
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = definitions
    end
  end
end
