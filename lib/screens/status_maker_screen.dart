import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:deva_aura/models/wallpaper_model.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:deva_aura/services/rate_app_service.dart';

class StatusMakerScreen extends StatefulWidget {
  final WallpaperModel wallpaper;

  const StatusMakerScreen({super.key, required this.wallpaper});

  @override
  State<StatusMakerScreen> createState() => _StatusMakerScreenState();
}

class _StatusMakerScreenState extends State<StatusMakerScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  // Template State
  int _selectedTemplateIndex =
      0; // 0=None, 1=Suprabhat, 2=Mantra, 3=Frame, 4=Quote
  String _customText = "Om Namah Shivaya";
  Offset _textPosition = const Offset(100, 100);
  double _textScale = 1.0;
  Color _textColor = Colors.white;
  TextStyle _selectedFont = GoogleFonts.poppins();

  final List<TextStyle> _fontOptions = [
    GoogleFonts.poppins(fontWeight: FontWeight.bold),
    GoogleFonts.dancingScript(fontWeight: FontWeight.bold),
    GoogleFonts.merriweather(fontWeight: FontWeight.w900),
    GoogleFonts.greatVibes(fontWeight: FontWeight.bold),
  ];
  final List<String> _fontNames = ["Modern", "Cursive", "Serif", "Royal"];

  final List<String> _predefinedTexts = [
    "Om Namah Shivaya",
    "Jai Shri Ram",
    "Radhe Radhe",
    "Jai Mata Di",
    "Har Har Mahadev",
    "Subh Prabhat", // Good Morning
    "Shubh Ratri", // Good Night
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Create Status'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.orangeAccent),
            onPressed: _captureAndShare,
          )
        ],
      ),
      body: Column(
        children: [
          // 1. Preview Area
          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _repaintKey,
                child: AspectRatio(
                  aspectRatio: 9 / 16, // Typical Status aspect ratio
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base Image
                      CachedNetworkImage(
                        imageUrl: widget.wallpaper.imageUrl,
                        fit: BoxFit.cover,
                      ),

                      // Template Layers
                      if (_selectedTemplateIndex == 1) _buildSuprabhatOverlay(),
                      if (_selectedTemplateIndex == 2) _buildMantraOverlay(),
                      if (_selectedTemplateIndex == 3) _buildVignetteOverlay(),
                      if (_selectedTemplateIndex == 4) _buildOmOverlay(),
                      if (_selectedTemplateIndex == 5) _buildFrameOverlay(),
                      if (_selectedTemplateIndex == 6) _buildQuoteOverlay(),

                      // Draggable Custom Text
                      Positioned(
                        left: _textPosition.dx,
                        top: _textPosition.dy,
                        child: GestureDetector(
                          onTap: () => _showTextInputDialog(),
                          onPanUpdate: (details) {
                            setState(() {
                              _textPosition += details.delta;
                            });
                          },
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              _customText,
                              textAlign: TextAlign.center,
                              style: _selectedFont.copyWith(
                                color: _textColor,
                                fontSize: 24 * _textScale,
                                shadows: [
                                  const Shadow(
                                      color: Colors.black, blurRadius: 4),
                                  if (_selectedTemplateIndex ==
                                      4) // Glow for Quote
                                    const Shadow(
                                        color: Colors.white, blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Controls Area
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.all(16.0),
            height: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Templates list
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildTemplateChip(0, "None", Icons.block),
                      _buildTemplateChip(1, "Suprabhat", Icons.wb_sunny),
                      _buildTemplateChip(2, "Mantra", Icons.self_improvement),
                      _buildTemplateChip(3, "Vignette", Icons.filter_vintage),
                      _buildTemplateChip(4, "Om", Icons.spa),
                      _buildTemplateChip(5, "Frame", Icons.border_outer),
                      _buildTemplateChip(6, "Quote", Icons.format_quote),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Predefined Texts
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _predefinedTexts.length,
                    itemBuilder: (context, index) {
                      final txt = _predefinedTexts[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          label: Text(txt),
                          onPressed: () => setState(() => _customText = txt),
                        ),
                      );
                    },
                  ),
                ),

                // Fine controls (Size/Color)
                Row(
                  children: [
                    const Text('Size:', style: TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        value: _textScale,
                        min: 0.5,
                        max: 3.0,
                        onChanged: (v) => setState(() => _textScale = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.color_lens, color: Colors.white),
                      onPressed: () => _pickColor(),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.font_download, color: Colors.white),
                      onPressed: () => _pickFont(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      onPressed: () => _showTextInputDialog(),
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

  // -- Template Builders --

  Widget _buildSuprabhatOverlay() {
    // Saffron gradient at top + "Suprabhat" text
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orangeAccent, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.center,
        ),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 40),
      // Typically Suprabhat is fixed, but user can edit existing text object to match
      child: Text(
        "Shubh Prabhat",
        style: GoogleFonts.poppins(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: [const Shadow(color: Colors.black45, blurRadius: 8)]),
      ),
    );
  }

  Widget _buildMantraOverlay() {
    return Container(
      color: Colors.black45, // Darker for mantra focus
      alignment: Alignment.center,
    );
  }

  Widget _buildVignetteOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
          radius: 0.85,
          stops: const [0.6, 1.0],
        ),
      ),
    );
  }

  Widget _buildOmOverlay() {
    return Center(
      child: Text(
        '🕉️',
        style: TextStyle(
          fontSize: 200,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildFrameOverlay() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFD700), width: 12),
      ),
    );
  }

  Widget _buildQuoteOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 100,
        width: double.infinity,
        color: Colors.black54,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        // The draggable text can be moved here manually
      ),
    );
  }

  Widget _buildTemplateChip(int index, String label, IconData icon) {
    bool isSelected = _selectedTemplateIndex == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          children: [
            Icon(icon,
                size: 16, color: isSelected ? Colors.white : Colors.black),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        selectedColor: Colors.orange,
        onSelected: (bool selected) {
          setState(() {
            _selectedTemplateIndex = selected ? index : 0;
            if (index == 1)
              _customText = ""; // Clear text for Suprabhat fixed text
            if (index == 0) _customText = "Om Namah Shivaya"; // Reset
          });
        },
      ),
    );
  }

  void _pickColor() {
    // Simple toggle for now: White -> Yellow -> Orange -> Black
    setState(() {
      if (_textColor == Colors.white)
        _textColor = Colors.yellow;
      else if (_textColor == Colors.yellow)
        _textColor = Colors.orange;
      else if (_textColor == Colors.orange)
        _textColor = Colors.black;
      else
        _textColor = Colors.white;
    });
  }

  Future<void> _captureAndShare() async {
    try {
      RenderRepaintBoundary? boundary = _repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      if (boundary.debugNeedsPaint) {
        // Wait for frame?
        await Future.delayed(const Duration(milliseconds: 20));
      }

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();

        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/status_share.png').create();
        await file.writeAsBytes(pngBytes);

        await Share.shareXFiles([XFile(file.path)],
            text: 'Created with DivineWall');

        // [NEW] Ask for review after sharing (high-engagement moment)
        if (mounted) {
          RateAppService().bumpLaunchAndMaybePrompt(context);
        }
      }
    } catch (e) {
      debugPrint('Error capturing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    }
  }

  void _pickFont() {
    // Determine next font index
    int loopIndex = 0;
    // Find current font in options if possible
    // Simplified: just cycle through styles for now
    setState(() {
      final currentIdx = _fontOptions
          .indexWhere((s) => s.fontFamily == _selectedFont.fontFamily);
      final nextIdx = (currentIdx + 1) % _fontOptions.length;
      _selectedFont = _fontOptions[nextIdx];
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Font: ${_fontNames[_fontOptions.indexOf(_selectedFont)]}'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 250),
      ),
    );
  }

  Future<void> _showTextInputDialog() async {
    final controller = TextEditingController(text: _customText);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Edit Text', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter your status text",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _customText = controller.text);
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}
