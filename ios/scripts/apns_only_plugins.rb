# Firebase Messaging remains a Dart/Android dependency. Its iOS registrar also
# installs delegates and registers APNs before Firebase initialization, so remove
# that one generated registration after generation and before native compilation.
module IOSAPNsPlugins
  REGISTRATION = /^[\t ]*\[FLTFirebaseMessagingPlugin\s+registerWithRegistrar:\s*\[registry\s+registrarForPlugin:\s*@"FLTFirebaseMessagingPlugin"\]\];[\t ]*(?:\r?\n|$)/.freeze

  def self.filter_registrant(source)
    filtered = source.gsub(REGISTRATION, '')
    if filtered.match?(/FLTFirebaseMessagingPlugin\s+registerWithRegistrar:/)
      raise 'Unexpected iOS Firebase Messaging registration; update the APNs-only filter before building.'
    end
    filtered
  end

  def self.remove_fcm_registration!(path)
    raise 'Flutter GeneratedPluginRegistrant.m is missing; run flutter pub get first.' unless File.file?(path)

    source = File.binread(path)
    filtered = filter_registrant(source)
    File.binwrite(path, filtered) unless filtered == source
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: apns_only_plugins.rb <GeneratedPluginRegistrant.m>' unless ARGV.length == 1
  IOSAPNsPlugins.remove_fcm_registration!(ARGV.fetch(0))
end
