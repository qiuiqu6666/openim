require 'minitest/autorun'
require 'tempfile'
require_relative '../apns_only_plugins'

class APNsOnlyPluginsTest < Minitest::Test
  def registration(plugin, newline = "\n")
    "  [#{plugin} registerWithRegistrar:[registry registrarForPlugin:@\"#{plugin}\"]];#{newline}"
  end

  def test_generated_registrar_keeps_local_notifications_and_unrelated_plugins
    local = registration('FlutterLocalNotificationsPlugin')
    core = registration('FLTFirebaseCorePlugin')
    im = registration('FlutterOpenimSdkPlugin')
    source = local + registration('FLTFirebaseMessagingPlugin') + core + im
    assert_equal local + core + im, IOSAPNsPlugins.filter_registrant(source)
  end

  def test_filter_survives_repeated_pod_install_and_flutter_regeneration
    source = registration('FLTFirebaseMessagingPlugin', "\r\n") + registration('FlutterLocalNotificationsPlugin', "\r\n")
    Tempfile.create(['registrant', '.m']) do |file|
      File.binwrite(file.path, source)
      2.times { IOSAPNsPlugins.remove_fcm_registration!(file.path) }
      expected = registration('FlutterLocalNotificationsPlugin', "\r\n")
      assert_equal expected, File.binread(file.path)
      File.binwrite(file.path, source) # flutter regenerates before an Xcode build
      IOSAPNsPlugins.remove_fcm_registration!(file.path)
      assert_equal expected, File.binread(file.path)
    end
  end

  def test_changed_fcm_generator_shape_fails_instead_of_enabling_a_second_push_path
    source = '[FLTFirebaseMessagingPlugin registerWithRegistrar:someOtherRegistrar];'
    assert_raises(RuntimeError) { IOSAPNsPlugins.filter_registrant(source) }
  end

  def test_absent_generated_source_requires_generation_before_build
    assert_raises(RuntimeError) { IOSAPNsPlugins.remove_fcm_registration!('/missing/GeneratedPluginRegistrant.m') }
  end
end
