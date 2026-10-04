import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import 'venue_code.dart';
import 'venue_page.dart';

/// Scan a venue's Trace poster (spec F-16).
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final code = venueCodeFrom(b.rawValue ?? '');
      if (code != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VenuePage(code: code)));
        return;
      }
    }
    setState(() => _hint = 'That’s not a Trace code.');
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).width * 0.68;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text('The camera isn’t available. Check camera access in Settings.',
                    textAlign: TextAlign.center, style: serif(size: 20, color: Colors.white)),
              ),
            ),
          ),
          // Dim everything outside the viewfinder.
          IgnorePointer(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
              child: Stack(
                children: [
                  Container(decoration: const BoxDecoration(color: Colors.transparent, backgroundBlendMode: BlendMode.dstOut)),
                  Center(
                    child: Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(Radii.lg)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(color: TraceColors.ember, width: 2.5),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Close'),
                      const Spacer(),
                      OrbButton(icon: Icons.flashlight_on_rounded, onTap: _controller.toggleTorch, tooltip: 'Torch'),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(
                    _hint ?? 'Point at a Trace poster or sticker.',
                    textAlign: TextAlign.center,
                    style: serif(size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
