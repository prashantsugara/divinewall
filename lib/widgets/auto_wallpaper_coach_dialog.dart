import 'package:flutter/material.dart';
import 'package:deva_aura/screens/auto_wallpaper_settings_screen.dart';

class AutoWallpaperCoachDialog extends StatelessWidget {
  const AutoWallpaperCoachDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 10,
      backgroundColor: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon / Header
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 48,
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Fresh Look, Every Day!',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Body
            Text(
              'Did you know? You can automatically change your wallpaper from your favorite categories without lifting a finger.',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Main Action
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AutoWallpaperSettingsScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "Let's Do It!",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),

            // Secondary Action
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe Later'),
            ),
          ],
        ),
      ),
    );
  }
}
