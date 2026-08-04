import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({super.key, required this.image});

  final Uint8List image;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  CropController _controller = CropController();
  var _generation = 0;
  var _ready = false;
  var _cropping = false;
  var _canUndo = false;
  var _canRedo = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090F1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090F1C),
        foregroundColor: Colors.white,
        title: const Text('Ajustar foto'),
        actions: [
          TextButton(
            onPressed: _ready && !_cropping ? _crop : null,
            child: const Text('Usar foto'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Crop(
                    key: ValueKey(_generation),
                    controller: _controller,
                    image: widget.image,
                    withCircleUi: true,
                    interactive: true,
                    fixCropRect: true,
                    maskColor: Colors.black.withValues(alpha: 0.68),
                    baseColor: Colors.black,
                    cornerDotBuilder: (_, _) => const SizedBox.shrink(),
                    initialRectBuilder: InitialRectBuilder.withBuilder((
                      viewport,
                      _,
                    ) {
                      final size = (viewport.shortestSide - 32).clamp(
                        120.0,
                        560.0,
                      );
                      return Rect.fromCenter(
                        center: viewport.center,
                        width: size,
                        height: size,
                      );
                    }),
                    willUpdateScale: (scale) => scale <= 8,
                    onStatusChanged: (status) {
                      if (!mounted) return;
                      setState(() => _ready = status == CropStatus.ready);
                    },
                    onHistoryChanged: (history) {
                      if (!mounted) return;
                      setState(() {
                        _canUndo = history.undoCount > 0;
                        _canRedo = history.redoCount > 0;
                      });
                    },
                    onCropped: (result) {
                      if (!mounted) return;
                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          Navigator.pop(context, croppedImage);
                        case CropFailure():
                          setState(() => _cropping = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo recortar la foto. Prueba otra imagen.',
                              ),
                            ),
                          );
                      }
                    },
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Pellizca para acercar o alejar y arrastra para centrar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Deshacer',
                  onPressed: _canUndo ? _controller.undo : null,
                  icon: const Icon(Icons.undo),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _reset,
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('Centrar de nuevo'),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Rehacer',
                  onPressed: _canRedo ? _controller.redo : null,
                  icon: const Icon(Icons.redo),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _crop() {
    setState(() => _cropping = true);
    _controller.crop();
  }

  void _reset() {
    setState(() {
      _controller = CropController();
      _generation++;
      _ready = false;
      _canUndo = false;
      _canRedo = false;
    });
  }
}
