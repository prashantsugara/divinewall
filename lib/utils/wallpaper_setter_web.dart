import 'wallpaper_setter_stub.dart';

WallpaperSetter getWallpaperSetter() => _WebWallpaperSetter();

class _WebWallpaperSetter implements WallpaperSetter {
  @override
  Future<bool> setFromUrl(String imageUrl,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    return false;
  }

  @override
  Future<bool> setFromFile(String path,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    return false;
  }
}
