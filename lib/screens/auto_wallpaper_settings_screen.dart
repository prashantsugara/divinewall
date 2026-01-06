import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:deva_aura/services/auto_wallpaper_service.dart';
import 'package:deva_aura/services/category_service.dart';
import 'package:deva_aura/models/category_model.dart';
import 'package:deva_aura/auth/auth_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:deva_aura/services/rewarded_ad_service.dart';
import 'package:deva_aura/utils/wallpaper_setter.dart';
import 'package:deva_aura/services/native_service.dart';
import 'package:deva_aura/services/rate_app_service.dart';

class AutoWallpaperSettingsScreen extends StatefulWidget {
  const AutoWallpaperSettingsScreen({super.key});

  @override
  State<AutoWallpaperSettingsScreen> createState() =>
      _AutoWallpaperSettingsScreenState();
}

class _AutoWallpaperSettingsScreenState
    extends State<AutoWallpaperSettingsScreen> {
  final _auth = AuthManager();
  final _categoryService = CategoryService();

  bool _enabled = false;
  AutoWallpaperSource _source = AutoWallpaperSource.favorites;
  String? _categoryId;
  int _frequency = 60; // minutes
  WallpaperScreenTarget _target = WallpaperScreenTarget.home;
  WallpaperColorTone _lockTone = WallpaperColorTone.normal;

  bool _saving = false;
  bool _gating = false;

  @override
  void initState() {
    super.initState();
    _load();
    // [NEW] Preload rewarded ad when opening settings to improve match rate
    RewardedAdService.instance.load(debugReason: 'autowall_settings_open');
  }

  Future<void> _load() async {
    final s = await AutoWallpaperSettings.load();
    if (!mounted) return;
    setState(() {
      _enabled = s.enabled;
      _source = s.source;
      _categoryId = s.categoryId;
      // [FIX] Sanitize frequency to avoid dropdown crash if legacy value (1) exists
      const validFreqs = [15, 30, 60, 360, 1440];
      if (validFreqs.contains(s.frequencyMinutes)) {
        _frequency = s.frequencyMinutes;
      } else {
        _frequency = 60; // Default fallback
      }
      _target = s.target;
      _lockTone = s.lockTone;
    });
  }

  Future<void> _save() async {
    debugPrint(
        '[AutoWallUI] Save clicked. Enabled: $_enabled, Source: $_source');
    setState(() => _saving = true);
    final platform = Theme.of(context).platform;
    try {
      // Gate with Rewarded Ad if enabling
      if (_enabled) {
        final notifOk = await _ensureNotificationsAllowed();
        if (!notifOk) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Please enable notifications to use Daily Darshan.')),
          );
          return;
        }

        // Feature: Skip ad for first time usage
        final isFirstTime =
            await AutoWallpaperService.instance.isFirstTimeUser();

        if (!isFirstTime) {
          debugPrint('[AutoWallUI] Showing rewarded ad...');
          final rewarded = await RewardedAdService.instance
              .showReward(debugReason: 'save_auto_wall');
          if (!rewarded) {
            debugPrint('[AutoWallUI] Ad not completed/failed.');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Ad not completed. Settings not saved. Please watch the ad to enable.')),
            );
            return; // Abort save
          }
          debugPrint('[AutoWallUI] Ad completed.');
        } else {
          debugPrint('[AutoWallUI] First time user - skipping ad!');
        }
      }

      // Proceed to save
      final finalCategoryId =
          _source == AutoWallpaperSource.category ? _categoryId : null;

      // [FIX] If Category source is selected but ID is null (default selection case), fetch the first one
      if (_source == AutoWallpaperSource.category &&
          (finalCategoryId == null || finalCategoryId.isEmpty)) {
        debugPrint('[AutoWallUI] Category ID missing. Fetching default...');
        try {
          final cats = await _categoryService.getCategories();
          if (cats.isNotEmpty) {
            // We use a local var because we can't easily change finalCategoryId after assignment
            // So let's reconstruct the settings object below
          }
        } catch (e) {
          debugPrint('[AutoWallUI] Failed to fetch default category: $e');
        }
      }

      String? effectiveCategoryId = finalCategoryId;
      if (_source == AutoWallpaperSource.category &&
          effectiveCategoryId == null) {
        final cats = await _categoryService.getCategories();
        if (cats.isNotEmpty) {
          effectiveCategoryId = cats.first.id;
          debugPrint(
              '[AutoWallUI] Using default category: ${cats.first.name} ($effectiveCategoryId)');
        }
      }

      final settings = AutoWallpaperSettings(
        enabled: _enabled && !kIsWeb && (platform == TargetPlatform.android),
        source: _source,
        frequencyMinutes: _frequency,
        categoryId: effectiveCategoryId,
        target: _target,
        lockTone: _lockTone,
      );

      debugPrint('[AutoWallUI] Saving settings to prefs...');
      await settings.save();

      final user = await _auth.getCurrentUserModel();
      debugPrint('[AutoWallUI] Refreshing pool...');
      final pool = await AutoWallpaperService.instance
          .refreshPool(currentUserId: user?.id);
      debugPrint('[AutoWallUI] Pool refreshed. Size: ${pool.length}');

      debugPrint('[AutoWallUI] Applying scheduling (immediate update)...');
      final ok = await AutoWallpaperService.instance.applyScheduling();
      debugPrint('[AutoWallUI] Scheduling applied. Result: $ok');

      await AutoWallpaperService.instance.handlePostSave(settings);

      if (_enabled) {
        await AutoWallpaperService.instance.markFirstTimeUserAsDone();
      }

      if (!mounted) {
        debugPrint('[AutoWallUI] Context not mounted after save.');
        return;
      }

      if (settings.enabled && !ok) {
        // Saved, but immediate trigger failed
        if (pool.isEmpty) {
          debugPrint('[AutoWallUI] Pool empty.');
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('No Wallpapers Found'),
              content: const Text(
                  'We couldn\'t find any wallpapers for your selection. Please try a different source or category.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK')),
              ],
            ),
          );
          return;
        }

        debugPrint('[AutoWallUI] Showing delayed dialog.');
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Saved with Delay'),
            content: const Text(
                'Settings saved, but we couldn\'t set the first wallpaper immediately (e.g. poor connection).\n\nIt will retry automatically in the background!'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK')),
            ],
          ),
        );
      } else {
        // Success or Disabled
        debugPrint('[AutoWallUI] Showing success dialog.');
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(settings.enabled ? 'Success!' : 'Disabled'),
            content: Text(settings.enabled
                ? 'Daily Darshan is set successfully!\n\nUpdates: Every ${_frequency == 1440 ? "day" : "$_frequency minutes"}.'
                : 'Daily Darshan has been disabled.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK')),
            ],
          ),
        );

        // [NEW] Ask for review after successful setup
        if (mounted) {
          RateAppService().bumpLaunchAndMaybePrompt(context);
        }
      }
    } catch (e, st) {
      debugPrint('[AutoWallUI][Error] Save failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _ensureNotificationsAllowed() async {
    try {
      // 1. Notifications
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final res = await Permission.notification.request();
        if (!res.isGranted) {
          if (!mounted) return false;
          // Show dialog for notifications...
          // (Existing logic simplified or kept)
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Enable notifications'),
              content: const Text(
                  'Notifications are required for the Daily Darshan feature.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () async {
                      await openAppSettings();
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    child: const Text('Open Settings')),
              ],
            ),
          );
          if (ok != true) return false;
        }
      }

      // 2. Battery Optimization (Android only)
      if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
        // Show explanation dialog first?
        // User requirement: "Show a one-time, non-forceful explanation screen"
        // We can do this check if it's not ignored using a plugin, but "permission_handler"
        // ignoreBatteryOptimizations is for requesting the permission.

        // Let's blindly ask for it nicely via NativeService once.
        // Or just call it.
        await NativeService.instance.requestBatteryOptimization();
      }

      return true;
    } catch (e) {
      debugPrint('[AutoWall][Gate][Warn] Perm check failed: $e');
      return false;
    }
  }

  Future<void> _handleToggleRequested(bool value) async {
    if (value == _enabled) return;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAndroid = !kIsWeb && theme.platform == TargetPlatform.android;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Daily Darshan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary.withValues(alpha: 0.15),
              cs.surface,
            ],
            stops: const [0.0, 0.4],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 100),
          children: [
            if (!isAndroid)
              _WarningCard(
                icon: Icons.warning_amber_rounded,
                text:
                    'Daily Darshan works on Android only (iOS/Web restriction).',
                color: cs.error,
              ),
            _SectionHeader(title: 'Source', icon: Icons.image),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SelectionCard(
                    label: 'Favorites',
                    icon: Icons.favorite_rounded,
                    color: Colors.redAccent,
                    isSelected: _source == AutoWallpaperSource.favorites,
                    onTap: () =>
                        setState(() => _source = AutoWallpaperSource.favorites),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SelectionCard(
                    label: 'Category',
                    icon: Icons.category_rounded,
                    color: Colors.amber,
                    isSelected: _source == AutoWallpaperSource.category,
                    onTap: () =>
                        setState(() => _source = AutoWallpaperSource.category),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SelectionCard(
                    label: 'Day-Wise',
                    icon: Icons.calendar_today_rounded,
                    color: Colors.purpleAccent,
                    isSelected: _source == AutoWallpaperSource.dayWise,
                    onTap: () =>
                        setState(() => _source = AutoWallpaperSource.dayWise),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SelectionCard(
                    label: 'Random',
                    icon: Icons.shuffle_rounded,
                    color: Colors.blueAccent,
                    isSelected: _source == AutoWallpaperSource.random,
                    onTap: () =>
                        setState(() => _source = AutoWallpaperSource.random),
                  ),
                ),
              ],
            ),
            if (_source == AutoWallpaperSource.dayWise) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_month_rounded,
                            size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Weekly Schedule',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildDayRow('Monday', 'Lord Shiva'),
                    _buildDayRow('Tuesday', 'Lord Hanuman'),
                    _buildDayRow('Wednesday', 'Lord Ganesha'),
                    _buildDayRow('Thursday', 'Lord Vishnu'),
                    _buildDayRow('Friday', 'Goddess Lakshmi'),
                    _buildDayRow('Saturday', 'Hanuman/Shani'),
                    _buildDayRow('Sunday', 'Lord Surya'),
                  ],
                ),
              ),
            ],
            if (_source == AutoWallpaperSource.category) ...[
              const SizedBox(height: 16),
              StreamBuilder<List<CategoryModel>>(
                stream: _categoryService.getCategoriesStream(),
                builder: (context, snapshot) {
                  final cats = snapshot.data ?? const <CategoryModel>[];
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _categoryId?.isNotEmpty == true
                            ? _categoryId
                            : (cats.isNotEmpty ? cats.first.id : null),
                        isExpanded: true,
                        hint: const Text('Select a category'),
                        items: cats
                            .map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 32),
            _SectionHeader(title: 'Update Schedule', icon: Icons.timer),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _frequency,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded,
                      color: cs.primary),
                  items: const [
                    DropdownMenuItem(
                        value: 15, child: Text('Every 15 minutes')),
                    DropdownMenuItem(
                        value: 30, child: Text('Every 30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('Every 1 hour')),
                    DropdownMenuItem(value: 360, child: Text('Every 6 hours')),
                    DropdownMenuItem(value: 1440, child: Text('Every day')),
                  ],
                  onChanged: (v) => setState(() => _frequency = v ?? 60),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionHeader(title: 'Where to Apply', icon: Icons.smartphone),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _RadioCard<WallpaperScreenTarget>(
                    value: WallpaperScreenTarget.home,
                    groupValue: _target,
                    label: 'Home',
                    icon: Icons.home_rounded,
                    onChanged: (v) => setState(() => _target = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RadioCard<WallpaperScreenTarget>(
                    value: WallpaperScreenTarget.lock,
                    groupValue: _target,
                    label: 'Lock',
                    icon: Icons.lock_rounded,
                    onChanged: (v) => setState(() => _target = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RadioCard<WallpaperScreenTarget>(
                    value: WallpaperScreenTarget.both,
                    groupValue: _target,
                    label: 'Both',
                    icon: Icons.mobile_friendly_rounded,
                    onChanged: (v) => setState(() => _target = v!),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _target == WallpaperScreenTarget.home
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        const SizedBox(height: 24),
                        _SectionHeader(
                            title: 'Lock Screen Style', icon: Icons.palette),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _RadioCard<WallpaperColorTone>(
                                value: WallpaperColorTone.normal,
                                groupValue: _lockTone,
                                label: 'Color',
                                icon: Icons.format_paint_rounded,
                                onChanged: (v) =>
                                    setState(() => _lockTone = v!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RadioCard<WallpaperColorTone>(
                                value: WallpaperColorTone.blackAndWhite,
                                groupValue: _lockTone,
                                label: 'B & W',
                                icon: Icons.filter_b_and_w_rounded,
                                onChanged: (v) =>
                                    setState(() => _lockTone = v!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: cs.secondary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Daily Darshan disables after 7 days. You’ll get a reminder to check back in!',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _EnableButton(
                enabled: _enabled,
                busy: _gating,
                onTap: () => _handleToggleRequested(!_enabled),
              ),
            ),
            const SizedBox(width: 16),
            FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              elevation: 2,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(String day, String deity) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              day,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              deity,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100, // Fixed width for horizontal scroll
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? color : cs.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? color : cs.onSurfaceVariant, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : cs.onSurface,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioCard<T> extends StatelessWidget {
  final T value;
  final T groupValue;
  final String label;
  final IconData icon;
  final ValueChanged<T?> onChanged;

  const _RadioCard({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 20,
                color:
                    isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _WarningCard(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _EnableButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _EnableButton(
      {required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.green.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? Colors.green : cs.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                  enabled
                      ? Icons.power_settings_new_rounded
                      : Icons.power_off_rounded,
                  color: enabled ? Colors.green : cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              enabled ? 'ENABLED' : 'DISABLED',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1,
                color: enabled ? Colors.green : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
