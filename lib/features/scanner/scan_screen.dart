import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/scanner/scan_result_screen.dart';

enum _ScanPhase { scanning, checking, notFound }

class _NoCameraPlaceholder extends StatelessWidget {
  const _NoCameraPlaceholder({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Qayta urinish'),
          ),
          const SizedBox(height: 8),
          Text(
            "yoki kodni qo'lda / USB skaner bilan kiriting",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _ScanPhase _phase = _ScanPhase.scanning;
  String? _lastBarcode;
  bool _handling = false;

  ScannerController? _scannerController;
  ScannerErrorCode? _cameraError;
  int _scannerKey = 0;

  final _manualController = TextEditingController();
  final _manualFocus = FocusNode();

  String get _cameraMessage {
    switch (_cameraError) {
      case ScannerErrorCode.cameraUnavailable:
        return "Kamera topilmadi. Tashqi (USB) kamera ulab, "
            "'Qayta urinish' tugmasini bosing.";
      case ScannerErrorCode.permissionDenied:
        return "Kameraga ruxsat yo'q. Ruxsat bering yoki "
            "kodni qo'lda / USB skaner bilan kiriting.";
      case ScannerErrorCode.alreadyActive:
        return "Boshqa skaner ochiq.";
      case ScannerErrorCode.invalidImage:
      case ScannerErrorCode.unknown:
      case null:
        return "Kamera ishga tushirilmadi.";
    }
  }

  void _submitManual() {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    _manualController.clear();
    _lookupBarcode(value);
  }

  void _onCameraScanned(String value) {
    if (value.isEmpty) return;
    _lookupBarcode(value.trim());
  }

  void _onCameraError(ScannerException error) {
    if (!mounted) return;
    setState(() => _cameraError = error.code);
  }

  void _retryCamera() {
    setState(() {
      _cameraError = null;
      _scannerKey++;
    });
  }

  @override
  void dispose() {
    _manualController.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode(String barcode) async {
    if (_phase != _ScanPhase.scanning || _handling) return;
    final value = barcode.trim();
    if (value.isEmpty) return;

    _handling = true;
    await _scannerController?.pauseScanning();
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
    if (_cameraError == null) {
      await _scannerController?.resumeScanning();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _manualFocus.requestFocus();
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_manualFocus.hasFocus) _manualFocus.requestFocus();
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
              child: _cameraError != null
                  ? _NoCameraPlaceholder(
                      message: _cameraMessage,
                      onRetry: _retryCamera,
                    )
                  : UniversalBarcodeScanner(
                      key: ValueKey<int>(_scannerKey),
                      continuous: true,
                      onCreated: (controller) {
                        _scannerController = controller;
                      },
                      onScanned: _onCameraScanned,
                      onError: _onCameraError,
                    ),
            ),
            if (_phase == _ScanPhase.scanning && _cameraError == null)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
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
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(4),
                child: TextField(
                  controller: _manualController,
                  focusNode: _manualFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitManual(),
                  decoration: InputDecoration(
                    labelText: 'Kodni kiriting yoki USB skaner bilan o\'qing',
                    prefixIcon: const Icon(Icons.keyboard),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _submitManual,
                    ),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
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