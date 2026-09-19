import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';

final zonesProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, warehouseId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getZones(auth.token!, warehouseId)
      : Future.value([]);
});

final storageLocationsProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, warehouseId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getStorageLocations(auth.token!, warehouseId)
      : Future.value([]);
});

class WarehouseDetailScreen extends ConsumerWidget {
  const WarehouseDetailScreen({super.key, required this.warehouse});

  final Map<String, dynamic> warehouse;

  int get warehouseId => warehouse['id'] as int;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = warehouse['name'] ?? '';
    final city = warehouse['city'] ?? '';
    final role = warehouse['role'] ?? '';

    final zonesAsync = ref.watch(zonesProvider(warehouseId));
    final locationsAsync = ref.watch(storageLocationsProvider(warehouseId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('$name',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Zonalar'),
              Tab(text: 'Joylashuvlar'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${city.isNotEmpty ? city : ''} '
                      '${role.isNotEmpty ? '| $role' : ''}'
                          .trim(),
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ZonesTab(
                    warehouseId: warehouseId,
                    zonesAsync: zonesAsync,
                  ),
                  _LocationsTab(
                    warehouseId: warehouseId,
                    locationsAsync: locationsAsync,
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

class _ZonesTab extends ConsumerWidget {
  const _ZonesTab({required this.warehouseId, required this.zonesAsync});

  final int warehouseId;
  final AsyncValue<List<dynamic>> zonesAsync;

  Future<void> _addZone(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ZoneFormDialog(warehouseId: warehouseId),
    );
    if (created == true) {
      ref.invalidate(zonesProvider(warehouseId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _addZone(context, ref),
              icon: const Icon(Icons.add),
              label: const Text("+ Zona qo'shish"),
            ),
          ),
        ),
        Expanded(
          child: zonesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Xatolik: $err')),
            data: (zones) {
              if (zones.isEmpty) {
                return const Center(
                  child: Text(
                    "Zonalar topilmadi",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                itemCount: zones.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final zone = zones[index] as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: Text(zone['name'] ?? ''),
                    subtitle: Text(zone['zone_type'] ?? ''),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ZoneFormDialog extends ConsumerStatefulWidget {
  const _ZoneFormDialog({required this.warehouseId});

  final int warehouseId;

  @override
  ConsumerState<_ZoneFormDialog> createState() => _ZoneFormDialogState();
}

class _ZoneFormDialogState extends ConsumerState<_ZoneFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _zoneType;
  String? _error;
  bool _saving = false;

  static const _zoneTypes = [
    'cold_storage',
    'dry_storage',
    'quarantine',
    'other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        if (_zoneType != null && _zoneType!.isNotEmpty)
          'zone_type': _zoneType,
      };
      await ApiClient().createZone(auth.token!, widget.warehouseId, body);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Zona qo'shish"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nomi',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nomi majburiy' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _zoneType,
              decoration: const InputDecoration(
                labelText: 'Turi (ixtiyoriy)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tanlanmagan')),
                for (final t in _zoneTypes)
                  DropdownMenuItem<String?>(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _zoneType = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }
}

class _LocationsTab extends ConsumerWidget {
  const _LocationsTab({required this.warehouseId, required this.locationsAsync});

  final int warehouseId;
  final AsyncValue<List<dynamic>> locationsAsync;

  Future<void> _addLocation(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationFormDialog(warehouseId: warehouseId),
    );
    if (created == true) {
      ref.invalidate(storageLocationsProvider(warehouseId));
      ref.invalidate(zonesProvider(warehouseId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _addLocation(context, ref),
              icon: const Icon(Icons.add),
              label: const Text("+ Joylashuv qo'shish"),
            ),
          ),
        ),
        Expanded(
          child: locationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Xatolik: $err')),
            data: (locations) {
              if (locations.isEmpty) {
                return const Center(
                  child: Text(
                    "Joylashuvlar topilmadi",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                itemCount: locations.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final loc = locations[index] as Map<String, dynamic>;
                  final capacity = loc['capacity_units'];
                  final current = loc['current_units'] ?? 0;
                  final zoneName = loc['zone_name'];
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(loc['code'] ?? ''),
                    subtitle: Text(
                      zoneName != null && zoneName is String
                          ? zoneName
                          : 'Zonasiz',
                    ),
                    trailing: Text(
                      capacity != null ? '$current / $capacity' : '$current',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LocationFormDialog extends ConsumerStatefulWidget {
  const _LocationFormDialog({required this.warehouseId});

  final int warehouseId;

  @override
  ConsumerState<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends ConsumerState<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _aisleController = TextEditingController();
  final _rackController = TextEditingController();
  final _shelfController = TextEditingController();
  final _binController = TextEditingController();
  final _capacityController = TextEditingController();
  int? _zoneId;
  List<dynamic> _zones = [];
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _aisleController.dispose();
    _rackController.dispose();
    _shelfController.dispose();
    _binController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  num? _parseCapacity(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final body = <String, dynamic>{
        if (_zoneId != null) 'zone_id': _zoneId,
        'aisle': _aisleController.text.trim(),
        'rack': _rackController.text.trim(),
        'shelf': _shelfController.text.trim(),
        'bin': _binController.text.trim(),
        if (_parseCapacity(_capacityController.text) != null)
          'capacity_units': _parseCapacity(_capacityController.text),
      };
      await ApiClient()
          .createStorageLocation(auth.token!, widget.warehouseId, body);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Joylashuv qo'shish"),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<List<dynamic>>(
                  future: ApiClient()
                      .getZones(ref.read(authProvider).token ?? '', widget.warehouseId)
                      .catchError((_) => <dynamic>[]),
                  builder: (context, snapshot) {
                    _zones = snapshot.data ?? _zones;
                    return DropdownButtonFormField<int?>(
                      initialValue: _zoneId,
                      decoration: const InputDecoration(
                        labelText: 'Zona',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Tanlanmagan')),
                        for (final z in _zones)
                          DropdownMenuItem<int?>(
                            value: z['id'] as int?,
                            child: Text((z['name'] as String?) ?? ''),
                          ),
                      ],
                      onChanged: (v) => setState(() => _zoneId = v),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _codeField(_aisleController, 'Aisle (masalan A)'),
                const SizedBox(height: 16),
                _codeField(_rackController, 'Rack (masalan 03)'),
                const SizedBox(height: 16),
                _codeField(_shelfController, 'Shelf (masalan 02)'),
                const SizedBox(height: 16),
                _codeField(_binController, 'Bin (masalan 01)'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Sig\'im (ixtiyoriy)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }

  Widget _codeField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        hintText: 'Kod avtomatik hosil qilinadi',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Majburiy maydon' : null,
    );
  }
}