package com.bittruth.gwallpaper

import io.flutter.app.FlutterApplication
import androidx.work.Configuration

class Application : FlutterApplication(), Configuration.Provider {

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()
}
