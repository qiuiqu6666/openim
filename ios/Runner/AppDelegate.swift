import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    var replayKitChannel: FlutterMethodChannel! = nil
    var observeTimer: Timer?
    var inviteChannel: FlutterMethodChannel?
    var pendingInvite: String?
    var hasEmittedFirstSample = false;
    var chatNotifications: ChatCommunicationNotificationBridge?
    var callPictureInPicture: CallPictureInPictureBridge?
    var deviceSyncOriginals: DeviceSyncOriginalsBridge?
    private var locationAddressBridge: ChatLocationAddressBridge?
    private let apnsPush = IOSAPNsPushBridge()
    private let voipCalls = IOSVoIPCallBridge()
    private let youmeng = YoumengBridge()
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        voipCalls.start()
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        apnsPush.attach(messenger: controller.binaryMessenger)
        youmeng.attach(messenger: controller.binaryMessenger)
        voipCalls.attach(messenger: controller.binaryMessenger)
        pendingInvite = (launchOptions?[.url] as? URL)?.absoluteString
        inviteChannel = FlutterMethodChannel(name: "openim_friend_invites", binaryMessenger: controller.binaryMessenger)
        inviteChannel?.setMethodCallHandler { [weak self] call, result in
            guard call.method == "takeInvite" else { result(FlutterMethodNotImplemented); return }
            let value = self?.pendingInvite
            self?.pendingInvite = nil
            result(value)
        }
        
        replayKitChannel = FlutterMethodChannel(name: "io.livekit.example.flutter/replaykit-channel",binaryMessenger: controller.binaryMessenger)
        
        replayKitChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping  FlutterResult)  -> Void in
            self.handleReplayKitFromFlutter(result: result, call:call)
        })
        
        locationAddressBridge = ChatLocationAddressBridge(messenger: controller.binaryMessenger)
        GeneratedPluginRegistrant.register(with: self)
        if let registrar = controller.registrar(forPlugin: "HomeNativeNavigation") {
            registrar.register(HomeTabBarFactory(registrar: registrar, parent: controller),
                               withId: "openim/home-tab-bar")
        }
        controller.registrar(forPlugin: "NativeChatLocationMap")?.register(
            NativeChatLocationMapFactory(messenger: controller.binaryMessenger),
            withId: "openim/chat-location-map")
        deviceSyncOriginals = DeviceSyncOriginalsBridge(messenger: controller.binaryMessenger)
        callPictureInPicture = CallPictureInPictureBridge(controller: controller)
        controller.registrar(forPlugin: "GroupLiveCast")?.register(
            LiveAirPlayViewFactory(),
            withId: "openim_group_live_airplay_picker")
        chatNotifications = ChatCommunicationNotificationBridge(
            messenger: controller.binaryMessenger)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
        guard ["chat99", "openim"].contains(url.scheme?.lowercased() ?? ""), url.host == "user" else {
            return super.application(app, open: url, options: options)
        }
        let value = url.absoluteString
        pendingInvite = value
        inviteChannel?.invokeMethod("openInvite", arguments: value) { [weak self] result in
            if result as? Bool == true && self?.pendingInvite == value {
                self?.pendingInvite = nil
            }
        }
        return true
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
