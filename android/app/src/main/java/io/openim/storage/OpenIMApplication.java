package io.openim.storage;

import android.app.Application;
import android.content.Context;
import android.system.ErrnoException;
import android.system.Os;
import android.util.Log;

import java.io.File;

/** Prepares native SQLite before Flutter plugins or the OpenIM SDK start. */
public final class OpenIMApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        io.openim.messaging.NativeMessageNotifications.get(this);
    }

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        // OpenIM bundles its own SQLite. Android's framework SQLite temporary
        // directory does not configure that copy. Large ORDER BY queries spill
        // to disk and otherwise fall back to the read-only process directory /.
        File temporaryDirectory = getCacheDir();
        if (temporaryDirectory == null || !temporaryDirectory.isDirectory()
                || !temporaryDirectory.canWrite()) {
            Log.e("OpenIMStorage", "SQLite temporary directory is unavailable");
            return;
        }
        try {
            Os.setenv("SQLITE_TMPDIR", temporaryDirectory.getAbsolutePath(), true);
        } catch (ErrnoException error) {
            Log.e("OpenIMStorage", "Cannot configure SQLite temporary directory", error);
        }
    }
}
