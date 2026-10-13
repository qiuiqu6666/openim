package io.openim.messaging

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import io.openim.flutter_openim_sdk.runtime.NativeIMRuntime

/** A started, same-process service; system stop is respected, never a restart loop. */
class IMService : Service() {
    override fun onCreate() {
        super.onCreate()
        NativeIMRuntime.get().attachApplication(applicationContext)
        Log.i("NativeIMService", "created; existing process runtime retained")
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!NativeIMRuntime.get().isInitialized || NativeIMRuntime.get().accountID().isEmpty()) stopSelf(startId)
        return START_NOT_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        Log.i("NativeIMService", "stopped; no forced restart, SDK lifetime remains process-owned")
        super.onDestroy()
    }
    companion object {
        fun startIfAllowed(context: Context) {
            if (!NativeIMRuntime.get().isForeground) return
            try { context.startService(Intent(context, IMService::class.java)) }
            catch (error: IllegalStateException) { Log.i("NativeIMService", "Background service start not allowed") }
        }
    }
}
