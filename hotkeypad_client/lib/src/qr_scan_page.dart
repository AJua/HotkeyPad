import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

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
  /// Guards against `onScan` firing again — for the next frame, while this
  /// screen has already started popping with a result.
  bool _handled = false;

  bool _cameraFailed = false;

  String? _notAHostMessage;

  void _onScan(Code code) {
    if (_handled) return;
    final raw = code.text;
    final parsed = raw == null ? null : WifiPairingQr.tryParse(raw);
    if (parsed != null) {
      _handled = true;
      Navigator.of(context).pop(parsed);
      return;
    }
    // Something was decoded — a real QR code, just not this app's — worth
    // a word rather than silently doing nothing forever.
    if (mounted) {
      setState(
        () => _notAHostMessage = AppLocalizations.of(context)!.invalidHostQr,
      );
    }
  }

  void _onControllerCreated(Object? controller, Exception? error) {
    if (error != null && mounted) setState(() => _cameraFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanHostQrTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.cameraPermissionDenied,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ReaderWidget(
              onScan: _onScan,
              onControllerCreated: _onControllerCreated,
              codeFormat: Format.qrCode,
              showFlashlight: false,
              showGallery: false,
              showToggleCamera: false,
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
