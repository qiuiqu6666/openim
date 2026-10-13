package io.openim.gameshield;

import android.content.Context;
import org.json.JSONObject;
import java.io.File;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/** Reflection keeps disabled builds free of a second gomobile runtime. */
final class GameShieldAndroidClient {
    private final Object client;
    private final Class<?> type;
    final String version;

    static boolean available() {
        try {
            Class.forName("com.gameshield.sdk.mobile.Mobile", false,
                    GameShieldAndroidClient.class.getClassLoader());
            return true;
        } catch (ClassNotFoundException error) { return false; }
    }

    GameShieldAndroidClient(Context context, String token) throws Exception {
        Class<?> mobile = Class.forName("com.gameshield.sdk.mobile.Mobile");
        version = (String) mobile.getMethod("version").invoke(null);
        if (!"60.1.10".equals(version)) throw new IllegalStateException("Unsupported SDK version");
        File directory = new File(context.getNoBackupFilesDir(), "gameshield");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IllegalStateException("Private SDK directory unavailable");
        }
        type = Class.forName("com.gameshield.sdk.mobile.Client");
        client = mobile.getMethod("newClientWithToken", String.class, String.class)
                .invoke(null, token, directory.getAbsolutePath());
    }
    private Object invoke(String name) throws Exception {
        return type.getMethod(name).invoke(client);
    }
    void start() throws Exception {
        type.getMethod("setAutoChangePort", boolean.class).invoke(client, true);
        invoke("start");
    }
    void stop() throws Exception { invoke("stop"); }
    void networkChanged() throws Exception { invoke("notifyNetworkChanged"); }
    void foreground() throws Exception { invoke("notifyForeground"); }
    Map<String, Object> snapshot() throws Exception {
        Map<String, Object> value = new HashMap<>();
        value.put("ready", invoke("ready"));
        value.put("sdkVersion", version);
        value.put("activeTunnels", ((Number) invoke("activeTunnels")).intValue());
        long count = ((Number) invoke("endpointCount")).longValue();
        if (count < 0 || count > 1024) throw new IllegalStateException("Invalid endpoint count");
        ArrayList<Map<String, Object>> endpoints = new ArrayList<>();
        Method read = type.getMethod("endpointAt", long.class);
        for (long index = 0; index < count; index++) {
            JSONObject endpoint = new JSONObject((String) read.invoke(client, index));
            Map<String, Object> item = new HashMap<>();
            item.put("appId", endpoint.getString("app_id"));
            item.put("groupName", endpoint.getString("group_name"));
            item.put("host", endpoint.getString("virtual_ip"));
            item.put("port", endpoint.getInt("virtual_port"));
            item.put("protocol", endpoint.getString("protocol"));
            endpoints.add(item);
        }
        value.put("endpoints", endpoints);
        Map<String, Integer> tcpPorts = new HashMap<>();
        Method currentPort = type.getMethod("currentTCPPort", long.class);
        // Ports in this application's four configured service rules.
        for (int originalPort : new int[]{10008, 10002, 10001, 8815}) {
            tcpPorts.put(Integer.toString(originalPort),
                    ((Number) currentPort.invoke(client, (long) originalPort)).intValue());
        }
        value.put("tcpPorts", tcpPorts);
        return value;
    }
}
