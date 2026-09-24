import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/scanner/scan_result_screen.dart';

enum _ScanPhase { scanning, checking, notFound }

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  _ScanPhase _phase = _ScanPhase.scanning;
  String? _lastBarcode;
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode(String barcode) async {
    if (_phase != _ScanPhase.scanning || _handling) return;
    final value = barcode.trim();
    if (value.isEmpty) return;

    _handling = true;
    await _controller.stop();
    if (mounted) setState(() => _phase = _ScanPhase.checking);

    final auth = ref.read(authProvider);
    if (auth.token == null) {
      _showMessage('Avval tizimga kiring');
      _resetScanning();
      return;
    }

    Map<String, dynamic>? found;
    ScanResultType foundType = ScanResultType.product;
    try {
      final container =
          await ApiClient().getContainerByBarcode(auth.token!, value);
      if (container != null) {
        found = container;
        foundType = ScanResultType.container;
      } else {
        final product = await ApiClient().getProductByBarcode(auth.token!, value);
        if (product != null) {
          found = product;
          foundType = ScanResultType.product;
        }
      }
    } on ApiException catch (e) {
      _handling = false;
      if (!mounted) return;
      _showMessage(e.message);
      await _resetScanning();
      return;
    }

    if (!mounted) return;

    if (found == null) {
      setState(() {
        _phase = _ScanPhase.notFound;
        _lastBarcode = value;
        _handling = false;
      });
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanResultScreen(type: foundType, data: found!),
      ),
    );
    if (!mounted) return;
    _handling = false;
    await _resetScanning();
  }

  Future<void> _resetScanning() async {
    if (!mounted) return;
    setState(() => _phase = _ScanPhase.scanning);
    await _controller.start();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _errorBuilder(BuildContext context, MobileScannerException error) {
    final isPermission =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPermission ? Icons.no_photography : Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            isPermission
                ? 'Kameraga ruxsat berilmagan, Tizim sozlamalaridan ruxsat bering'
                : 'Kamera ishga tushirilmadi',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _controller.start(),
            icon: const Icon(Icons.refresh),
            label: const Text('Qayta urinish'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skaner')),
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  final barcodes = capture.barcodes;
                  if (barcodes.isEmpty) return;
                  final value = barcodes.first.rawValue;
                  if (value == null || value.isEmpty) return;
                  _lookupBarcode(value);
                },
                errorBuilder: _errorBuilder,
              ),
            ),
            if (_phase == _ScanPhase.scanning)
              IgnorePointer(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Shtrix kodni kameraga tuting',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            if (_phase == _ScanPhase.checking)
              const ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Qidirilmoqda...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            if (_phase == _ScanPhase.notFound)
              Container(
                color: Theme.of(context).colorScheme.surface,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 56,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$_lastBarcode',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bunday shtrix kodli narsa topilmadi',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _resetScanning,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Qayta skanerlash'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}