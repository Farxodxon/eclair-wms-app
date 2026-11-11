import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/config.dart';
import 'package:wms_app/core/offline/offline_banner.dart';
import 'package:wms_app/core/offline/offline_controller.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/auth/login_screen.dart';
import 'package:wms_app/features/products/product_list_screen.dart';
import 'package:wms_app/features/warehouses/warehouse_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initServerConfig();
  runApp(const ProviderScope(child: WmsApp()));
}

class WmsApp extends ConsumerWidget {
  const WmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    ref.watch(offlineControllerProvider);

    return MaterialApp(
      title: 'WMS',
      scaffoldMessengerKey: rootMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      builder: (context, child) => Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      home: auth.status == AuthStatus.loggedIn
          ? (auth.isOperator
              ? const ProductListScreen()
              : const WarehouseListScreen())
          : const LoginScreen(),
    );
  }
}