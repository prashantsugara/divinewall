# Flutter R8/ProGuard Rules

# Force build validation even with warnings
-ignorewarnings

# Ignore AndroidX Window Extensions (Foldable support) missing classes
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }

# Keep Flutter embedding classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep AlarmManager classes
# Keep AlarmManager classes
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# Keep Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Firebase & AdMob (Prevent stripping of required classes)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Gson (Required for Auto Wallpaper JSON parsing)
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.stream.** { *; }
# Keep generic type tokens used in WallpaperExecutor
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.bittruth.gwallpaper.WallpaperExecutor$** { *; }
