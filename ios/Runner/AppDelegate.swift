import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    var replayKitChannel: FlutterMethodChannel! = nil
    var observeTimer: Timer?
    private let friendInvites = FriendInviteBridge()
    var hasEmittedFirstSample = false;
    var chatNotifications: ChatCommunicationNotificationBridge?
    var callPictureInPicture: CallPictureInPictureBridge?
    var deviceSyncOriginals: DeviceSyncOriginalsBridge?
    private var locationAddressBridge: ChatLocationAddressBridge?
    private let apnsPush = IOSAPNsPushBridge()
    private let voipCalls = IOSVoIPCallBridge()
    private let youmeng = YoumengBridge()
    private var mediaAudioBridge: MediaAudioBridge?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        voipCalls.start()
        if let url = launchOptions?[.url] as? URL {
            _ = handleFriendInvite(url)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // UIScene creates the window after process launch. Register the engine's
    // plugins/channels here instead of reading AppDelegate.window at launch.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        let registry = engineBridge.pluginRegistry
        let messenger = engineBridge.applicationRegistrar.messenger()
        GeneratedPluginRegistrant.register(with: registry)

        apnsPush.attach(messenger: messenger)
        mediaAudioBridge = MediaAudioBridge(messenger: messenger)
        youmeng.attach(messenger: messenger)
        voipCalls.attach(messenger: messenger)
        friendInvites.attach(messenger: messenger)
        replayKitChannel = FlutterMethodChannel(name: "io.livekit.example.flutter/replaykit-channel",binaryMessenger: messenger)
        
        replayKitChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping  FlutterResult)  -> Void in
            self.handleReplayKitFromFlutter(result: result, call:call)
        })
        
        locationAddressBridge = ChatLocationAddressBridge(messenger: messenger)
        if let registrar = registry.registrar(forPlugin: "HomeNativeNavigation") {
            registrar.register(HomeTabBarFactory(registrar: registrar),
                               withId: "openim/home-tab-bar")
        }
        registry.registrar(forPlugin: "NativeChatLocationMap")?.register(
            NativeChatLocationMapFactory(messenger: messenger),
            withId: "openim/chat-location-map")
        deviceSyncOriginals = DeviceSyncOriginalsBridge(messenger: messenger)
        if let registrar = registry.registrar(forPlugin: "CallPictureInPicture") {
            callPictureInPicture = CallPictureInPictureBridge(messenger: messenger) {
                registrar.viewController as? FlutterViewController
            }
        }
        registry.registrar(forPlugin: "GroupLiveCast")?.register(
            LiveAirPlayViewFactory(),
            withId: "openim_group_live_airplay_picker")
        chatNotifications = ChatCommunicationNotificationBridge(
            messenger: messenger)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        apnsPush.didRegister(deviceToken: deviceToken)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        apnsPush.didFailToRegister(error: error)
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.trigger is UNPushNotificationTrigger {
            // The OpenIM message runtime owns foreground notifications.
            completionHandler([])
            return
        }
        super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.trigger is UNPushNotificationTrigger {
            apnsPush.didReceive(response: response)
            completionHandler()
            return
        }
        // Local chat notifications retain their plugin payload/click delivery.
        super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
    
    override func application(_ app: UIApplication, open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if handleFriendInvite(url) { return true }
        return super.application(app, open: url, options: options)
    }

    @discardableResult
    func handleFriendInvite(_ url: URL) -> Bool {
        friendInvites.open(url)
    }

    func handleReplayKitFromFlutter(result:FlutterResult, call: FlutterMethodCall){
        switch (call.method) {
        case "startReplayKit":
            self.hasEmittedFirstSample = false
            let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(false, forKey: "closeReplayKitFromNative")
            group!.set(false, forKey: "closeReplayKitFromFlutter")
            self.observeReplayKitStateChanged()
            break
        case "closeReplayKit":
            let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(true,forKey: "closeReplayKitFromFlutter")
            result(true)
            break
        default:
            return result(FlutterMethodNotImplemented)
        }
    }
    

    func observeReplayKitStateChanged(){
        if (self.observeTimer != nil) {
            return
        }
        
        let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
        self.observeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (timer) in
            let closeReplayKitFromNative=group!.bool(forKey: "closeReplayKitFromNative")
            let hasSampleBroadcast=group!.bool(forKey: "hasSampleBroadcast")
            
            if (closeReplayKitFromNative) {
                self.hasEmittedFirstSample = false
                self.replayKitChannel.invokeMethod("closeReplayKitFromNative", arguments: true)
            } else if (hasSampleBroadcast) {
                if (!self.hasEmittedFirstSample) {
                    self.hasEmittedFirstSample = true
                    self.replayKitChannel.invokeMethod("hasSampleBroadcast", arguments: true)
                }
            }
        }
    }
}
