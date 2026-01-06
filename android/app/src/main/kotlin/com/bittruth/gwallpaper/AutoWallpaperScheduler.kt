package com.bittruth.gwallpaper

import android.content.Context
import androidx.work.*
import com.google.gson.Gson
import java.util.concurrent.TimeUnit

object AutoWallpaperScheduler {
    private const val WORK_NAME = "auto_wallpaper_work"

    fun start(context: Context, frequencyMinutes: Long, urls: List<String>, targetIndex: Int, lockToneIndex: Int) {
        // 1. Save Pool
        val prefs = context.getSharedPreferences(WallpaperWorker.PREFS_NAME, Context.MODE_PRIVATE)
        val gson = Gson()
        prefs.edit()
            .putString(WallpaperWorker.KEY_URL_POOL, gson.toJson(urls))
            .putLong("frequency_minutes", frequencyMinutes)
            .putInt(WallpaperWorker.KEY_TARGET, targetIndex)
            .putInt(WallpaperWorker.KEY_LOCK_TONE, lockToneIndex)
            .commit() // Use commit() to ensure synchronous save before Trigger runs

        // 2. Schedule Work
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED) // Need internet to download
            // .setRequiresBatteryNotLow(true) // Optional, maybe too aggressive if we want reliability
            .build()
        
        // WorkManager minimum periodic interval is 15 minutes.
        // If frequency < 15, we can't use PeriodicWorkRequest strictly for exact timing.
        // However, User requested 15 min, 1h, 6h, 1 day. 15 min is the minimum.
        // So PeriodicWorkRequest is perfect.
        
        val actualFrequency = if (frequencyMinutes < 15) 15L else frequencyMinutes

        val workRequest = PeriodicWorkRequestBuilder<WallpaperWorker>(
            actualFrequency, TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .setBackoffCriteria(
                BackoffPolicy.LINEAR,
                WorkRequest.MIN_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE, // Cancel and Re-schedule
            workRequest
        )
        
        // Also Trigger Immediate One-Time Work?
        // User requirements: "Cancel and replace existing work when frequency changes"
        // Usually we want an immediate update upon setting new wallpaper logic.
        // But the Periodic worker might not run immediately.
        // Let's also launch a OneTimeWork to "start" things off if desired.
        // For now, let's rely on the Flutter side or User interaction to set the FIRST wallpaper,
        // OR we can trigger a OneTimeWork here.
        // Ideally, when user clicks "Save", we might want to change wallpaper NOW.
        // But often the PeriodicWork will run shortly.
        // WorkManager `UPDATE` policy might fetch the first run.
    }

    fun stop(context: Context) {
        val prefs = context.getSharedPreferences(WallpaperWorker.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(WallpaperWorker.KEY_URL_POOL).apply()
        
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    fun updatePool(context: Context, urls: List<String>) {
        val prefs = context.getSharedPreferences(WallpaperWorker.PREFS_NAME, Context.MODE_PRIVATE)
        val gson = Gson()
        prefs.edit()
            .putString(WallpaperWorker.KEY_URL_POOL, gson.toJson(urls))
            .apply()
    }
    
    fun triggerImmediate(context: Context) {
        val request = OneTimeWorkRequestBuilder<WallpaperWorker>()
             .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
             .build()
        WorkManager.getInstance(context).enqueue(request)
    }

    fun triggerImmediateDirect(context: Context) {
        // Run in a background thread immediately, bypassing WorkManager queue
        // Using GlobalScope or just a thread since this is a "fire and forget" from UI perspective but we want speed.
        // Better to use a standard thread to avoid CoroutineScope complexity without a lifecycle component here.
        Thread {
            try {
                // Blocking call for the thread
                kotlinx.coroutines.runBlocking {
                    WallpaperExecutor.execute(context)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }.start()
    }
    
    fun getLastRunTime(context: Context): Long {
        val prefs = context.getSharedPreferences(WallpaperWorker.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(WallpaperWorker.KEY_LAST_RUN, 0L)
    }
}
