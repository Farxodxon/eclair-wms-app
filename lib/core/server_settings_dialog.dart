import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/core/config.dart';

Future<void> showServerSettingsDialog(BuildContext context) async {
  final controller = TextEditingController(text: apiBaseUrl);
  String? status;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Server manzili'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Masalan: 192.168.1.50:8080',
                  border: OutlineInputBorder(),
                ),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(status!),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              setLocal(() => status = 'Tekshirilmoqda...');
              try {
                final url = normalizeServerUrl(controller.text);
                await Dio(BaseOptions(
                  connectTimeout: const Duration(seconds: 5),
                  receiveTimeout: const Duration(seconds: 5),
                )).get('$url/health');
                setLocal(() => status = 'Ulandi (OK)');
              } catch (_) {
                setLocal(() => status = "Ulanib bo'lmadi");
              }
            },
            child: const Text('Tekshirish'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    ),
  );

  if (saved == true && controller.text.trim().isNotEmpty) {
    await saveServerUrl(controller.text);
    ApiClient.setBaseUrl(apiBaseUrl);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server: $apiBaseUrl')),
      );
    }
  }
}