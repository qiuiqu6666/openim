import UIKit
import Flutter
import FirebaseCore
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
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        FirebaseApp.configure()
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
        
        GeneratedPluginRegistrant.register(with: self)
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
    
    override func application(_ app: UIApplication, open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "openim", url.host == "user" else {
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
