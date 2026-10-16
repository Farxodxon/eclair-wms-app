import 'package:flutter/material.dart';
import 'package:wms_app/core/api_client.dart';

class StockLookupScreen extends StatefulWidget {
  const StockLookupScreen({super.key});

  @override
  State<StockLookupScreen> createState() => _StockLookupScreenState();
}

class _StockLookupScreenState extends State<StockLookupScreen> {
  final _api = ApiClient();
  final _searchController = TextEditingController();
  List<dynamic> _allItems = [];
  List<dynamic> _filteredItems = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.getPublicStockSummary();
      setState(() {
        _allItems = items;
        _filteredItems = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredItems = query.isEmpty
          ? _allItems
          : _allItems
              .where((item) =>
                  (item['sku'] as String).toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Qoldiqlar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Kod bo\'yicha qidirish',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ) else if (_error != null) Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              ),
            ) else Expanded(
              child: _filteredItems.isEmpty
                  ? const Center(child: Text('Topilmadi'))
                  : ListView.separated(
                      itemCount: _filteredItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return ListTile(
                          title: Text(
                            item['sku'] as String,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: Text(
                            '${item['quantity']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}