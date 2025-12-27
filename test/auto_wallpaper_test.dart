import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deva_aura/services/auto_wallpaper_service.dart';
import 'package:deva_aura/utils/wallpaper_setter.dart';

class _FakeSetter implements WallpaperSetter {
  final List<String> calls = [];

  @override
  Future<bool> setFromFile(String path,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    calls.add(path);
    return true;
  }

  @override
  Future<bool> setFromUrl(String imageUrl,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    calls.add(imageUrl);
    return true;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses single favorite when pool contains one URL', () async {
    SharedPreferences.setMockInitialValues({
      'auto_wallpaper_pool_urls': ['fav1'],
      'auto_wallpaper_pool_index': 0,
    });

    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeSetter();
    setWallpaperSetterForTesting(fake);

    final res = await AutoWallpaperService.instance.applyScheduling();
    expect(res, isTrue);
    expect(fake.calls, isNotEmpty);
    expect(fake.calls.first, 'fav1');
    // pool index with single-item pool should wrap to 0
    expect(prefs.getInt('auto_wallpaper_pool_index'), 0);
  });

  test('rotates through pool on subsequent updates', () async {
    SharedPreferences.setMockInitialValues({
      'auto_wallpaper_pool_urls': ['a', 'b', 'c'],
      'auto_wallpaper_pool_index': 0,
    });

    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeSetter();
    setWallpaperSetterForTesting(fake);

    expect(await AutoWallpaperService.instance.applyScheduling(), isTrue);
    expect(fake.calls, ['a']);
    expect(prefs.getInt('auto_wallpaper_pool_index'), 1);

    fake.calls.clear();
    expect(await AutoWallpaperService.instance.applyScheduling(), isTrue);
    expect(fake.calls, ['b']);
    expect(prefs.getInt('auto_wallpaper_pool_index'), 2);

    fake.calls.clear();
    expect(await AutoWallpaperService.instance.applyScheduling(), isTrue);
    expect(fake.calls, ['c']);
    expect(prefs.getInt('auto_wallpaper_pool_index'), 0);
  });
}
