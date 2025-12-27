export 'wallpaper_setter_stub.dart'
    show
        WallpaperSetter,
        WallpaperApplyOptions,
        WallpaperScreenTarget,
        WallpaperColorTone;

// Ensure the public types are available to all consumers (including tests).
import 'wallpaper_setter_stub.dart'
    show
        WallpaperSetter,
        WallpaperApplyOptions,
        WallpaperScreenTarget,
        WallpaperColorTone;

import 'wallpaper_setter_stub.dart'
    if (dart.library.io) 'wallpaper_setter_mobile.dart'
    if (dart.library.html) 'wallpaper_setter_web.dart';

/// Mutable global used by production code. Tests may replace this via
/// `setWallpaperSetterForTesting` to inject a fake implementation.
WallpaperSetter wallpaperSetter = getWallpaperSetter();

/// Test-only helper to replace the global `wallpaperSetter` implementation.
/// Not intended for production use.
void setWallpaperSetterForTesting(WallpaperSetter setter) {
  wallpaperSetter = setter;
}
