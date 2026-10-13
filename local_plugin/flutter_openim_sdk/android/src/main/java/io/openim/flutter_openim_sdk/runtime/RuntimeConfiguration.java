package io.openim.flutter_openim_sdk.runtime;

import org.json.JSONObject;

/** Only an explicit shutdown may change transport or database identity. */
public final class RuntimeConfiguration {
    private RuntimeConfiguration() {}
    public static boolean matches(String a, String b) {
        try {
            JSONObject left = new JSONObject(a), right = new JSONObject(b);
            for (String key : new String[]{"platformID", "apiAddr", "wsAddr", "dataDir",
                    "isNeedEncryption", "isCompression", "systemType"}) {
                if (!String.valueOf(left.opt(key)).equals(String.valueOf(right.opt(key)))) return false;
            }
            return true;
        } catch (Exception ignored) { return false; }
    }
}
