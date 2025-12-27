import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class WallpaperEditScreen extends StatefulWidget {
  final File originalFile;

  const WallpaperEditScreen({super.key, required this.originalFile});

  @override
  State<WallpaperEditScreen> createState() => _WallpaperEditScreenState();
}

class _WallpaperEditScreenState extends State<WallpaperEditScreen> {
  late File _currentFile;
  bool _isProcessing = false;

  // Filter state
  double _blurRadius = 0;
  bool _isGrayscale = false;
  bool _isSepia = false;

  // We keep a history or just apply on save?
  // For simplicity: We show a preview. If user crops, we update _currentFile.
  // Filters are applied visually via ShaderMask or ColorFilter for preview,
  // and applied to the actual bytes upon "Save".

  @override
  void initState() {
    super.initState();
    _currentFile = widget.originalFile;
  }

  Future<void> _saveAndExit() async {
    // ... truncated
    setState(() => _isProcessing = true);
    try {
      if (_blurRadius == 0 && !_isGrayscale && !_isSepia) {
        if (mounted) Navigator.pop(context, _currentFile);
        return;
      }
      // ... truncated
      final rawBytes = await _currentFile.readAsBytes();
      // ... truncated
      final resultBytes = await compute(
          _applyFilters,
          _FilterRequest(
            bytes: rawBytes,
            blur: _blurRadius,
            grayscale: _isGrayscale,
            sepia: _isSepia,
          ));

      if (resultBytes == null) throw Exception("Filter application failed");

      // 3. Write to a new temp file
      final tempDir = await getTemporaryDirectory();
      final filteredFile = File(
          '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await filteredFile.writeAsBytes(resultBytes);

      if (mounted) {
        Navigator.pop(context, filteredFile);
      }
    } catch (e) {
      // ... truncated
      debugPrint('Edit save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save changes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build preview with filters applied visually
    // Add Key to force rebuild when file changes
    Widget preview = Image.file(_currentFile,
        fit: BoxFit.contain,
        key: ValueKey(_currentFile.path +
            '${DateTime.now().millisecondsSinceEpoch}')); // Timestamp ensures refresh even if path reused

    if (_blurRadius > 0) {
      // Flutter's ImageFiltered is great for preview
      // Note: SigmaX/Y is roughly blur radius
      preview = ImageFiltered(
        imageFilter:
            ui.ImageFilter.blur(sigmaX: _blurRadius, sigmaY: _blurRadius),
        child: preview,
      );
    }

    // Color filters are applied in a stack or chained?
    // ColorFiltered widget
    if (_isGrayscale) {
      preview = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: preview,
      );
    } else if (_isSepia) {
      preview = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.393,
          0.769,
          0.189,
          0,
          0,
          0.349,
          0.686,
          0.168,
          0,
          0,
          0.272,
          0.534,
          0.131,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: preview,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.black,
        title:
            const Text('Edit Wallpaper', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _saveAndExit,
            child: _isProcessing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('SAVE',
                    style: TextStyle(
                        color: Colors.amber, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(child: preview),
          ),
          // Controls
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Blur slider
                Row(
                  children: [
                    const Icon(Icons.blur_on, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _blurRadius,
                        min: 0,
                        max: 10,
                        activeColor: Colors.amber,
                        onChanged: (v) => setState(() => _blurRadius = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _FilterChip(
                      label: 'Normal',
                      selected: !_isGrayscale && !_isSepia,
                      onTap: () => setState(() {
                        _isGrayscale = false;
                        _isSepia = false;
                      }),
                    ),
                    _FilterChip(
                      label: 'Gray',
                      selected: _isGrayscale,
                      onTap: () => setState(() {
                        _isGrayscale = true;
                        _isSepia = false;
                      }),
                    ),
                    _FilterChip(
                      label: 'Sepia',
                      selected: _isSepia,
                      onTap: () => setState(() {
                        _isSepia = true;
                        _isGrayscale = false;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper class for isolate
class _FilterRequest {
  final Uint8List bytes;
  final double blur;
  final bool grayscale;
  final bool sepia;
  _FilterRequest(
      {required this.bytes,
      required this.blur,
      required this.grayscale,
      required this.sepia});
}

// Isolate function (must be static or top-level)
// Note: 'package:image' operations can be slow, so we run in isolate.
Future<Uint8List?> _applyFilters(_FilterRequest req) async {
  img.Image? image = img.decodeImage(req.bytes);
  if (image == null) return null;

  if (req.blur > 0) {
    // Gaussian blur kernel radius approx equal to sigma?
    // package:image uses integer radius.
    image = img.gaussianBlur(image, radius: req.blur.toInt());
  }

  if (req.grayscale) {
    image = img.grayscale(image);
  } else if (req.sepia) {
    image = img.sepia(image);
  }

  // Always re-encode to JPG
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.amber,
      labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
      backgroundColor: Colors.grey[800],
    );
  }
}
