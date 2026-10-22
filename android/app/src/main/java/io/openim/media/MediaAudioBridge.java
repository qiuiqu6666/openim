package io.openim.media;

import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Owns media focus and the built-in voice route, never an individual message. */
public final class MediaAudioBridge {
    private final Context context;
    private final AudioManager audio;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private String kind;
    private boolean speaker = true;
    private boolean ownsRoute;
    private boolean routeSuspended;
    private int previousMode;
    private AudioFocusRequest focus;
    private final AudioManager.OnAudioFocusChangeListener focusListener = change -> {
        if (change < 0) main.post(() -> interrupted());
    };
    private final AudioDeviceCallback devices = new AudioDeviceCallback() {
        @Override public void onAudioDevicesAdded(AudioDeviceInfo[] added) { refreshRoute(); }
        @Override public void onAudioDevicesRemoved(AudioDeviceInfo[] removed) { refreshRoute(); }
    };
    private final BroadcastReceiver noisy = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent intent) { interrupted(); }
    };

    public MediaAudioBridge(Context context, BinaryMessenger messenger) {
        this.context = context;
        audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        channel = new MethodChannel(messenger, "openim/media_audio");
        audio.registerAudioDeviceCallback(devices, main);
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(noisy,
            new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED);
        else context.registerReceiver(noisy, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
        channel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("snapshot")) {
                java.util.Map<String, Object> state = new java.util.HashMap<>();
                state.put("kind", kind);
                state.put("speaker", speaker);
                state.put("mode", audio.getMode());
                if (Build.VERSION.SDK_INT >= 31) {
                    AudioDeviceInfo selected = audio.getCommunicationDevice();
                    state.put("deviceType", selected == null ? null : selected.getType());
                } else state.put("speakerphone", audio.isSpeakerphoneOn());
                result.success(state);
                return;
            }
            if (!call.method.equals("configure")) { result.notImplemented(); return; }
            try {
                String requested = call.argument("kind");
                speaker = !"earpiece".equals(call.argument("output"));
                if (requested == null) { release(); result.success(null); return; }
                boolean starting = kind == null || !kind.equals(requested);
                kind = requested;
                if (routeSuspended && !starting) throw new IllegalStateException("Audio focus interrupted");
                routeSuspended = false;
                if (starting && !"recording".equals(kind)) requestFocus();
                if ("voice".equals(kind)) applyRoute(); else clearRoute();
                result.success(null);
            } catch (Exception error) {
                release();
                result.error("audio_route", error.getMessage(), null);
            }
        });
    }
    private void requestFocus() {
        AudioAttributes attributes = new AudioAttributes.Builder()
            .setUsage("voice".equals(kind) ? AudioAttributes.USAGE_VOICE_COMMUNICATION : AudioAttributes.USAGE_MEDIA)
            .setContentType("voice".equals(kind) ? AudioAttributes.CONTENT_TYPE_SPEECH : AudioAttributes.CONTENT_TYPE_MOVIE).build();
        int granted;
        if (Build.VERSION.SDK_INT >= 26) {
            focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener, main)
                .setWillPauseWhenDucked(true).build();
            granted = audio.requestAudioFocus(focus);
        } else granted = audio.requestAudioFocus(focusListener,
            "voice".equals(kind) ? AudioManager.STREAM_VOICE_CALL : AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN);
        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) throw new IllegalStateException("Audio focus denied");
    }
    private boolean external(AudioDeviceInfo device) {
        int type = device.getType();
        return type == AudioDeviceInfo.TYPE_WIRED_HEADSET || type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
            || type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            || type == AudioDeviceInfo.TYPE_USB_HEADSET || type == AudioDeviceInfo.TYPE_USB_DEVICE
            || type == AudioDeviceInfo.TYPE_HEARING_AID || type == 26 || type == 27;
    }
    private void applyRoute() {
        boolean accessory = false;
        for (AudioDeviceInfo device : audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            if (external(device)) { accessory = true; break; }
        }
        if (accessory) {
            // Let Android retain wired/Bluetooth output. User preference remains saved.
            if (Build.VERSION.SDK_INT >= 31) {
                AudioDeviceInfo current = audio.getCommunicationDevice();
                AudioDeviceInfo target = current != null && external(current) ? current : null;
                if (target == null) {
                    for (AudioDeviceInfo device : audio.getAvailableCommunicationDevices()) {
                        if (external(device)) { target = device; break; }
                    }
                }
                if (target != null) {
                    if (!ownsRoute) { previousMode = audio.getMode(); ownsRoute = true; }
                    audio.setMode(AudioManager.MODE_IN_COMMUNICATION);
                    if (!audio.setCommunicationDevice(target)) throw new IllegalStateException("Headset route unavailable");
                    return;
                }
            }
            clearRoute();
            return;
        }
        if (!ownsRoute) { previousMode = audio.getMode(); ownsRoute = true; }
        audio.setMode(AudioManager.MODE_IN_COMMUNICATION);
        if (Build.VERSION.SDK_INT >= 31) {
            int type = speaker ? AudioDeviceInfo.TYPE_BUILTIN_SPEAKER : AudioDeviceInfo.TYPE_BUILTIN_EARPIECE;
            AudioDeviceInfo target = null;
            for (AudioDeviceInfo device : audio.getAvailableCommunicationDevices()) {
                if (device.getType() == type) { target = device; break; }
            }
            if (target == null || !audio.setCommunicationDevice(target)) {
                throw new IllegalStateException("Requested audio output unavailable");
            }
        } else audio.setSpeakerphoneOn(speaker);
    }
    private void refreshRoute() {
        if (!"voice".equals(kind) || routeSuspended) return;
        try { applyRoute(); } catch (Exception error) { interrupted(); }
    }
    private void clearRoute() {
        if (!ownsRoute) return;
        if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice();
        else audio.setSpeakerphoneOn(false);
        if (audio.getMode() == AudioManager.MODE_IN_COMMUNICATION) audio.setMode(previousMode);
        ownsRoute = false;
    }
    private void interrupted() {
        if (kind != null && !"recording".equals(kind)) {
            // Restore our route before notifying Dart; late disposal must not
            // reset a new call's AudioManager mode.
            clearRoute();
            routeSuspended = true;
            channel.invokeMethod("interrupted", null);
        }
    }
    private void release() {
        kind = null;
        routeSuspended = false;
        clearRoute();
        if (Build.VERSION.SDK_INT >= 26 && focus != null) audio.abandonAudioFocusRequest(focus);
        else audio.abandonAudioFocus(focusListener);
        focus = null;
    }
    public void dispose() {
        release();
        audio.unregisterAudioDeviceCallback(devices);
        context.unregisterReceiver(noisy);
        channel.setMethodCallHandler(null);
    }
}
