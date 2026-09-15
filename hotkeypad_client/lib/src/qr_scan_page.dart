import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Scans a host's pairing QR code — see [WifiPairingQr] for the payload
/// format both ends agree on. Pops with the parsed result on a
/// successful scan, or null if the user backs out first.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController();

  /// Guards against `onDetect` firing again — for another frame, or for a
  /// second code still in view — after this screen has already started
  /// popping with a result.
  bool _handled = false;

  String? _notAHostMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final parsed = WifiPairingQr.tryParse(raw);
      if (parsed == null) continue;
      _handled = true;
      Navigator.of(context).pop(parsed);
      return;
    }
    // Something was decoded — a real QR code, just not this app's — worth
    // a word rather than silently doing nothing forever.
    if (capture.barcodes.isNotEmpty && mounted) {
      setState(
        () => _notAHostMessage = AppLocalizations.of(context)!.invalidHostQr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanHostQrTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.cameraPermissionDenied,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                _notAHostMessage ?? l10n.pointCameraAtQr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
