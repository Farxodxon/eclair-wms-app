import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wms_app/core/api_client.dart';

/// Internet (tashqi) manzil - qurilishda beriladi:
/// `--dart-define=INTERNET_SERVER_URL=http://100.x.y.z:8080`
const String _internetServerUrl = String.fromEnvironment(
  'INTERNET_SERVER_URL',
);

/// Hozirgi ishchi server manzili. Ustuvorlik:
/// 1) foydalanuvchi saqlagan fayl (server_settings_dialog)
/// 2) o'rnatuvchi yozgan server.txt (wms_app.exe yonida) - qatorlar bo'ylab
///    bir nechta manzil (birinchi javob bergani tanlanadi)
/// 3) --dart-define=API_BASE_URL, bo'lmasa http://localhost:8080
String apiBaseUrl = const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://eclair-wms-backend.onrender.com',
);

List<String> _candidates = [];

String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  // Port ko'rsatilmagan bo'lsa (masalan http://192.168.1.50) -> :8080
  if (RegExp(r'^http://[^/:]+$').hasMatch(url)) {
    url = '$url:8080';
  }
  return url;
}

Future<File> _userConfigFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}server.txt');
}

File _installerConfigFile() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  return File('$exeDir${Platform.pathSeparator}server.txt');
}

Future<String?> _readIfExists(File file) async {
  try {
    if (await file.exists()) {
      final text = (await file.readAsString()).trim();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {}
  return null;
}

List<String> _parseCandidates(String? raw) {
  final result = <String>[];
  void addIf(String url) {
    final normalized = normalizeServerUrl(url);
    if (normalized.isEmpty) return;
    if (!result.contains(normalized)) result.add(normalized);
  }

  if (raw != null) {
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      if (line.trim().isNotEmpty) addIf(line);
    }
  }
  final defaultUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://eclair-wms-backend.onrender.com',
  );
  addIf(defaultUrl);
  if (_internetServerUrl.isNotEmpty) addIf(_internetServerUrl);
  return result;
}

/// main() da, runApp'dan OLDIN chaqiriladi. Server manzillarni yuklaydi.
Future<void> loadServerConfig() async {
  String? raw;
  try {
    raw = await _readIfExists(await _userConfigFile());
  } catch (_) {}
  raw ??= await _readIfExists(_installerConfigFile());
  _candidates = _parseCandidates(raw);
  if (_candidates.isNotEmpty) {
    _applyServerUrl(_candidates.first);
  }
}

/// Avtomatik topish (fon): berilgan manzillarni sinab ko'radi, keyin
/// LAN subnetida 8080 portni skanerlaydi, oxirida internet manzili.
Future<void> discoverServer() async {
  if (_candidates.isEmpty) return;
  for (final candidate in _candidates) {
    if (await _probeHttp(candidate)) {
      _candidates.remove(candidate);
      _candidates.insert(0, candidate);
      _applyServerUrl(candidate);
      _saveDiscovered(candidate);
      return;
    }
  }
  final lanUrl = await _scanLan();
  if (lanUrl != null) {
    _applyServerUrl(lanUrl);
    _saveDiscovered(lanUrl);
  }
}

void _applyServerUrl(String url) {
  apiBaseUrl = url;
  try {
    ApiClient.setBaseUrl(url);
  } catch (_) {}
}

Future<void> _saveDiscovered(String url) async {
  try {
    final file = await _userConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(url);
  } catch (_) {}
}

Future<bool> _probeHttp(
  String url, {
  Duration connectTimeout = const Duration(milliseconds: 900),
}) async {
  try {
    final u = Uri.parse(url);
    final host = u.host;
    final port = u.hasPort ? u.port : 8080;
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    socket.write('GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
    await socket.flush();
    final chunk = await socket
        .first
        .timeout(const Duration(milliseconds: 800));
    socket.destroy();
    return utf8.decode(chunk, allowMalformed: true).startsWith('HTTP/');
  } catch (_) {
    return false;
  }
}

Future<String?> _scanLan() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final network in interfaces) {
      for (final address in network.addresses) {
        if (address.isLoopback || address.isLinkLocal) continue;
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        final prefix = parts.take(3).join('.');
        final ownLast = int.tryParse(parts[3]);
        final found = await _scanRange(prefix, ownLast);
        if (found != null) return found;
      }
    }
  } catch (_) {}
  return null;
}

Future<String?> _scanRange(String prefix, int? ownLast) async {
  const batchSize = 25;
  for (var start = 1; start <= 255; start += batchSize) {
    final batch = <Future<String?>>[];
    for (var last = start; last < start + batchSize && last <= 255; last++) {
      if (last == ownLast) continue;
      batch.add(_probeHost('$prefix.$last'));
    }
    final results = await Future.wait(batch);
    for (final result in results) {
      if (result != null) return result;
    }
  }
  return null;
}

Future<String?> _probeHost(String host) async {
  try {
    final socket = await Socket.connect(
      host,
      8080,
      timeout: const Duration(milliseconds: 300),
    );
    socket.write('GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
    await socket.flush();
    final chunk = await socket
        .first
        .timeout(const Duration(milliseconds: 400));
    socket.destroy();
    if (utf8.decode(chunk, allowMalformed: true).startsWith('HTTP/')) {
      return 'http://$host:8080';
    }
  } catch (_) {}
  return null;
}

Future<void> saveServerUrl(String raw) async {
  final url = normalizeServerUrl(raw);
  if (url.isEmpty) return;
  _applyServerUrl(url);
  try {
    if (!_candidates.contains(url)) {
      _candidates.remove(url);
      _candidates.insert(0, url);
    }
  } catch (_) {}
  final file = await _userConfigFile();
  await file.parent.create(recursive: true);
  await file.writeAsString(url);
}