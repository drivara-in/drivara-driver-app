package com.drivara.drivara_driver_android

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

class LocationService : Service() {
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("LocationService", "Service started natively")
        // TODO: Implement FusedLocationProviderClient logic here for "Unkillable" tracking
        // This runs in the native layer, separate from Flutter's UI thread.
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("LocationService", "Service destroyed")
    }
}
