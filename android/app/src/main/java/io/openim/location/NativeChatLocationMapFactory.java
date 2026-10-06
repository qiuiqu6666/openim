package io.openim.location;

import android.content.Context;

import androidx.lifecycle.Lifecycle;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public final class NativeChatLocationMapFactory extends PlatformViewFactory {
    private final Lifecycle lifecycle;
    private final BinaryMessenger messenger;
    private final Set<NativeChatLocationMap> views = new HashSet<>();

    public NativeChatLocationMapFactory(Lifecycle lifecycle, BinaryMessenger messenger) {
        super(StandardMessageCodec.INSTANCE);
        this.lifecycle = lifecycle;
        this.messenger = messenger;
    }

    @Override
    public PlatformView create(Context context, int viewId, Object arguments) {
        Map<?, ?> params = arguments instanceof Map ? (Map<?, ?>) arguments : null;
        NativeChatLocationMap view = new NativeChatLocationMap(
                context, lifecycle, messenger, viewId, params, views::remove);
        views.add(view);
        return view;
    }

    public void dispose() {
        for (NativeChatLocationMap view : new ArrayList<>(views)) view.dispose();
        views.clear();
    }
}
