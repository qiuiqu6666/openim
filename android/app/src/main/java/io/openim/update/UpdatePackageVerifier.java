package io.openim.update;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import androidx.core.content.pm.PackageInfoCompat;
import java.io.File;
import java.io.FileInputStream;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

final class UpdatePackageVerifier {
    static long number(Map<String, Object> args, String name) {
        Object value = args.get(name);
        if (!(value instanceof Number)) throw new IllegalArgumentException(name);
        return ((Number) value).longValue();
    }

    @SuppressWarnings("deprecation")
    static void verify(Context context, File file, Map<String, Object> args) throws Exception {
        if (!file.isFile() || file.length() != number(args, "size"))
            throw new IllegalStateException("APK size mismatch");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[128 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder hash = new StringBuilder();
        for (byte b : digest.digest()) hash.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
        if (!hash.toString().equals(args.get("sha256")))
            throw new IllegalStateException("APK checksum mismatch");
        PackageManager pm = context.getPackageManager();
        PackageInfo archive = pm.getPackageArchiveInfo(file.getAbsolutePath(), PackageManager.GET_SIGNATURES);
        PackageInfo installed = pm.getPackageInfo(context.getPackageName(), PackageManager.GET_SIGNATURES);
        if (archive == null || !context.getPackageName().equals(archive.packageName))
            throw new IllegalStateException("APK package name mismatch");
        long version = PackageInfoCompat.getLongVersionCode(archive);
        if (version != number(args, "versionCode") || version <= PackageInfoCompat.getLongVersionCode(installed)
                || !args.get("versionName").equals(archive.versionName))
            throw new IllegalStateException("APK version mismatch");
        // Exact signer equality deliberately fails closed on key rotation;
        // a planned rotation needs a separately reviewed lineage policy.
        Set<Signature> trusted = signatures(installed.signatures);
        if (trusted.isEmpty() || !trusted.equals(signatures(archive.signatures)))
            throw new IllegalStateException("APK signing certificate mismatch");
    }

    private static Set<Signature> signatures(Signature[] values) {
        Set<Signature> result = new HashSet<>();
        if (values != null) java.util.Collections.addAll(result, values);
        return result;
    }
}
