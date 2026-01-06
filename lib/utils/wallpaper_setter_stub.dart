enum WallpaperScreenTarget { home, lock, both }

enum WallpaperColorTone { normal, blackAndWhite }

class WallpaperApplyOptions {
  const WallpaperApplyOptions({
    this.target = WallpaperScreenTarget.home,
    this.lockColorTone = WallpaperColorTone.normal,
  });

  final WallpaperScreenTarget target;
  final WallpaperColorTone lockColorTone;

  WallpaperApplyOptions copyWith({
    WallpaperScreenTarget? target,
    WallpaperColorTone? lockColorTone,
  }) =>
      WallpaperApplyOptions(
        target: target ?? this.target,
        lockColorTone: lockColorTone ?? this.lockColorTone,
      );
}

abstract class WallpaperSetter {
  Future<bool> setFromUrl(String imageUrl,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()});
  Future<bool> setFromFile(String path,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()});
}

WallpaperSetter getWallpaperSetter() => _StubWallpaperSetter();

class _StubWallpaperSetter implements WallpaperSetter {
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
