import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/auth/login_screen.dart';
import 'package:wms_app/features/warehouses/warehouse_list_screen.dart';

void main() {
  runApp(const ProviderScope(child: WmsApp()));
}

class WmsApp extends ConsumerWidget {
  const WmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'WMS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: auth.status == AuthStatus.loggedIn
          ? const WarehouseListScreen()
          : const LoginScreen(),
    );
  }
}