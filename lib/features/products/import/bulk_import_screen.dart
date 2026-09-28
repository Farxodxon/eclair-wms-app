import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/import/import_planner.dart';
import 'package:wms_app/features/products/product_form_screen.dart';

const _rIgnore = 'ignore';
const _rSku = 'sku';
const _rName = 'name';
const _rShelfLife = 'shelf_life';
const _rSerial = 'serial';

String _rAttr(String key) => 'attr:$key';

/// Excel birinchi ustunidagi "No" belgisi (UTF-8 literal ishlatmaslik uchun
/// kod bilan yozilgan).
const symNo = '\u2116';

enum _Phase { setup, running, done }

class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  final _unitController = TextEditingController(text: 'kg');
  final _prefixController = TextEditingController(text: 'PLK-');

  String? _fileName;
  List<int>? _bytes;
  List<String> _sheetNames = [];
  String? _sheetName;
  bool _hasHeaderRow = true;
  ParsedSheet? _sheet;
  String? _readError;

  int? _categoryId;
  List<dynamic> _schema = [];

  final Map<int, String> _roles = {};
  bool _shelfLifeInMonths = true;

  ImportPlan? _plan;

  _Phase _phase = _Phase.setup;
  int _processed = 0;
  int _total = 0;
  int _createdCount = 0;
  bool _stopRequested = false;
  final List<SkippedRow> _runtimeSkipped = [];

  @override
  void dispose() {
    _unitController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- fayl

  Future<void> _pickFile() async {
    setState(() {
      _readError = null;
    });
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Excel faylni tanlang',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _readError = "Faylni o'qib bo'lmadi");
      return;
    }

    try {
      final names = sheetNames(bytes);
      setState(() {
        _fileName = picked.name;
        _bytes = bytes;
        _sheetNames = names;
        _sheetName = names.isNotEmpty ? names.first : null;
        _sheet = null;
        _plan = null;
        _phase = _Phase.setup;
        _roles.clear();
        _runtimeSkipped.clear();
        _createdCount = 0;
        _processed = 0;
        _total = 0;
      });
      _reloadSheet();
    } catch (e) {
      setState(() => _readError = 'Faylni ochib bo\'lmadi: $e');
    }
  }

  void _reloadSheet() {
    final bytes = _bytes;
    final name = _sheetName;
    if (bytes == null || name == null) return;
    try {
      final sheet = parseSheet(bytes, name);
      setState(() {
        _sheet = sheet;
        _plan = null;
        _phase = _Phase.setup;
        _roles.clear();
        _runtimeSkipped.clear();
        _createdCount = 0;
        _processed = 0;
        _total = 0;
      });
      _autoAssignRoles();
    } catch (e) {
      setState(() {
        _sheet = null;
        _readError = 'Varqani o\'qib bo\'lmadi: $e';
      });
    }
  }

  // ------------------------------------------------------------ kategoriya

  void _onCategoryChanged(int? id, List<dynamic> categories) {
    Map<String, dynamic>? chosen;
    for (final c in categories) {
      if (c is Map && c['id'] == id) {
        chosen = Map<String, dynamic>.from(c);
        break;
      }
    }
    setState(() {
      _categoryId = id;
      _schema = (chosen?['attribute_schema'] as List?) ?? const [];
      _plan = null;
      // atribut kalitlari o'zgargani uchun eski mosliklarni tozalaymiz
      _roles.removeWhere((_, role) =>
          role.startsWith('attr:') && !_schemaKeys.contains(role.substring(5)));
    });
  }

  Set<String> get _schemaKeys => {
        for (final e in _schema)
          if (e is Map && e['key'] is String) e['key'] as String,
      };

  // --------------------------------------------------- ustunlarni moslashtirish

  /// Sarlavha qatori mavjud bo'lsa, uning matniga qarab taxminiy moslik.
  void _autoAssignRoles() {
    final sheet = _sheet;
    if (sheet == null || !_hasHeaderRow || sheet.rows.isEmpty) return;
    final header = sheet.rows.first;
    final assign = <int, String>{};

    for (var i = 0; i < header.length; i++) {
      final h = header[i].trim().toLowerCase();
      if (h.isEmpty) continue;
      if (h.contains('код') || h == 'sku' || h.contains('code')) {
        assign[i] = _rSku;
      } else if (h.contains('ном') ||
          h.contains('назв') ||
          h.contains('name')) {
        assign[i] = _rName;
      } else if (h.contains('муддат') ||
          h.contains('ярокл') ||
          h.contains('яроқл') ||
          h.contains('срок') ||
          h.contains('shelf')) {
        assign[i] = _rShelfLife;
      } else if (h.startsWith(symNo) || h == 'no' || h == 'n') {
        assign[i] = _rSerial;
      }
    }

    // Kategoriya atributlari - sarlavhadagi label yoki kalit bo'yicha.
    for (final element in _schema) {
      if (element is! Map) continue;
      final key = element['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final label = (element['label'] as String? ?? key).trim().toLowerCase();
      for (var i = 0; i < header.length; i++) {
        if (assign.containsKey(i)) continue;
        final h = header[i].trim().toLowerCase();
        if (h.isEmpty) continue;
        if (h == key.toLowerCase() ||
            h == label ||
            (label.length > 3 && h.contains(label))) {
          assign[i] = _rAttr(key);
          break;
        }
      }
    }

    setState(() {
      _roles
        ..clear()
        ..addAll(assign);
    });
  }

  List<String> _roleOptions() {
    final options = <String>[
      _rIgnore,
      _rSku,
      _rName,
      _rShelfLife,
      _rSerial,
    ];
    for (final element in _schema) {
      if (element is! Map) continue;
      final key = element['key'] as String? ?? '';
      if (key.isEmpty) continue;
      options.add(_rAttr(key));
    }
    return options;
  }

  String _roleLabel(String role) {
    if (role == _rIgnore) return "E'tiborsiz qoldirish";
    if (role == _rSku) return 'SKU (kod)';
    if (role == _rName) return 'Nomi';
    if (role == _rShelfLife) return 'Yaroqlilik muddati';
    if (role == _rSerial) return 'Tartib raqam';
    final key = role.substring(5);
    for (final element in _schema) {
      if (element is Map && element['key'] == key) {
        return element['label'] as String? ?? key;
      }
    }
    return key;
  }

  List<String> _sampleValues(int column) {
    final sheet = _sheet;
    if (sheet == null) return const [];
    final start = _hasHeaderRow ? 1 : 0;
    final values = <String>[];
    for (var r = start; r < sheet.rows.length && values.length < 2; r++) {
      if (column >= sheet.rows[r].length) continue;
      final v = sheet.rows[r][column].trim();
      if (v.isNotEmpty) values.add(v);
    }
    return values;
  }

  // --------------------------------------------------------------- reja

  ImportMapping? _buildMapping() {
    final sheet = _sheet;
    if (sheet == null) return null;
    final unit = _unitController.text.trim();
    if (unit.isEmpty) return null;

    int? nameColumn;
    int? skuColumn;
    int? shelfLifeColumn;
    int? serialColumn;
    final attributes = <String, int>{};

    for (final entry in _roles.entries) {
      switch (entry.value) {
        case _rName:
          nameColumn = entry.key;
        case _rSku:
          skuColumn = entry.key;
        case _rShelfLife:
          shelfLifeColumn = entry.key;
        case _rSerial:
          serialColumn = entry.key;
        default:
          if (entry.value.startsWith('attr:')) {
            attributes[entry.value.substring(5)] = entry.key;
          }
      }
    }

    if (nameColumn == null) return null;

    return ImportMapping(
      hasHeaderRow: _hasHeaderRow,
      skuColumn: skuColumn,
      nameColumn: nameColumn,
      shelfLifeColumn: shelfLifeColumn,
      shelfLifeInMonths: _shelfLifeInMonths,
      attributeColumns: attributes,
      defaultUnit: unit,
      skuPrefix: _prefixController.text.trim(),
      serialColumn: serialColumn,
    );
  }

  void _runPreview() {
    final sheet = _sheet;
    final mapping = _buildMapping();
    if (sheet == null || mapping == null) {
      setState(() {
        _plan = null;
        _readError = "Avval 'Nomi' ustunini tanlang";
      });
      return;
    }
    setState(() {
      _readError = null;
      _plan = buildPlan(sheet, mapping);
      _phase = _Phase.setup;
    });
  }

  // -------------------------------------------------------------- import

  /// Atribut qiymatini kategoriya sxemasidagi turga moslab o'tkazadi.
  /// Noto'g'ri qiymatni tashlab yuboradi (butun importni to'xtatmasligi uchun).
  dynamic _convertAttribute(String type, String text) {
    switch (type) {
      case 'number':
        return num.tryParse(text);
      case 'bool':
        final v = text.toLowerCase();
        if (v == 'ha' || v == 'true' || v == '1' || v == 'yes') return true;
        if (v == 'yo\'q' || v == 'false' || v == '0' || v == 'no') return false;
        return null;
      case 'date':
        return DateTime.tryParse(text) != null ? text : null;
      default:
        return text;
    }
  }

  Map<String, dynamic>? _buildBody(PlannedProduct item) {
    final body = item.toBody();
    final types = <String, String>{};
    for (final element in _schema) {
      if (element is! Map) continue;
      final key = element['key'] as String?;
      final type = element['type'] as String? ?? 'text';
      if (key != null) types[key] = type;
    }

    final attributes = <String, dynamic>{};
    for (final entry in item.attributes.entries) {
      final type = types[entry.key];
      if (type == null) continue;
      final value = _convertAttribute(type, '${entry.value}');
      if (value != null) attributes[entry.key] = value;
    }
    body['attributes'] = attributes;
    body['category_id'] = _categoryId;
    return body;
  }

  Future<void> _runImport() async {
    final plan = _plan;
    final auth = ref.read(authProvider);
    if (plan == null || auth.token == null || _categoryId == null) return;

    final token = auth.token!;
    setState(() {
      _phase = _Phase.running;
      _stopRequested = false;
      _processed = 0;
      _total = plan.toCreate.length;
      _createdCount = 0;
      _runtimeSkipped.clear();
    });

    final items = plan.toCreate;
    // 5 tadan iborat parallel bo'laklar - bitta xato butun importni to'xtatmaydi.
    const chunkSize = 5;
    for (var start = 0; start < items.length; start += chunkSize) {
      if (_stopRequested) break;
      final end = (start + chunkSize).clamp(0, items.length);
      final chunk = items.sublist(start, end);

      final results = await Future.wait(chunk.map((item) async {
        final body = _buildBody(item);
        try {
          await ApiClient().createProduct(token, body!);
          return (item: item, error: null as String?);
        } on ApiException catch (e) {
          return (item: item, error: e.message);
        } catch (e) {
          return (item: item, error: '$e');
        }
      }));

      if (!mounted) return;
      setState(() {
        for (final r in results) {
          _processed++;
          if (r.error == null) {
            _createdCount++;
          } else {
            _runtimeSkipped.add(SkippedRow(
              rowNumber: r.item.rowNumber,
              sku: r.item.sku,
              name: r.item.name,
              reason: _skipReasonFor(r.error!),
            ));
          }
        }
      });
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.done);
  }

  String _skipReasonFor(String message) {
    if (message.contains('SKU')) return SkipReasons.existsInDb;
    return message;
  }

  void _resetToSetup() {
    setState(() {
      _phase = _Phase.setup;
      _plan = null;
      _runtimeSkipped.clear();
      _createdCount = 0;
      _processed = 0;
      _total = 0;
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Excel import')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFileSection(),
          const SizedBox(height: 16),
          if (_sheet != null) ...[
            _buildSheetSection(categoriesAsync),
            const SizedBox(height: 16),
            _buildMappingSection(),
            const SizedBox(height: 16),
          ],
          if (_phase == _Phase.running) ...[
            _buildProgress(),
            const SizedBox(height: 16),
          ],
          if (_phase == _Phase.done) ...[
            _buildReport(),
            const SizedBox(height: 16),
          ],
          if (_plan != null && _phase == _Phase.setup) ...[
            _buildPreview(),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildFileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: _phase == _Phase.running ? null : _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Excel fayl tanlash'),
            ),
            const SizedBox(height: 8),
            Text(
              _fileName == null ? 'Fayl tanlanmagan' : 'Fayl: $_fileName',
              style: TextStyle(
                fontSize: 14,
                color: _fileName == null ? Colors.grey : null,
              ),
            ),
            if (_readError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _readError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetSection(AsyncValue<List<dynamic>> categoriesAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _sheetName,
              decoration: const InputDecoration(
                labelText: 'Varaq',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final s in _sheetNames)
                  DropdownMenuItem<String>(value: s, child: Text(s)),
              ],
              onChanged: _phase == _Phase.running
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _sheetName = value;
                        _hasHeaderRow = true;
                      });
                      _reloadSheet();
                    },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Birinchi qator sarlavhami?"),
              value: _hasHeaderRow,
              onChanged: _phase == _Phase.running
                  ? null
                  : (value) {
                      setState(() {
                        _hasHeaderRow = value ?? true;
                        _plan = null;
                      });
                      _autoAssignRoles();
                    },
            ),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Kategoriya xatosi: $err'),
              data: (categories) => DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Kategoriya',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem<int?>(
                      value: c['id'] as int?,
                      child: Text(c['name'] as String? ?? ''),
                    ),
                ],
                onChanged: _phase == _Phase.running
                    ? null
                    : (value) => _onCategoryChanged(value, categories),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingSection() {
    final sheet = _sheet!;
    final options = _roleOptions();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ustunlarni moslashtirish',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < sheet.columnCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildColumnRow(i, options),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Muddat oy hisobidami?'),
              subtitle: const Text('Yoqiq bo\'lsa, qiymat kun deb hisoblanadi'),
              value: _shelfLifeInMonths,
              onChanged: _phase == _Phase.running
                  ? null
                  : (value) {
                      setState(() {
                        _shelfLifeInMonths = value ?? true;
                        _plan = null;
                      });
                    },
            ),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Standart birlik',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _plan = null),
              enabled: _phase != _Phase.running,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefixController,
              decoration: const InputDecoration(
                labelText: 'SKU prefiksi',
                helperText: 'SKU ustuni tanlanmaganda ishlatiladi',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _plan = null),
              enabled: _phase != _Phase.running,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _phase == _Phase.running ? null : _runPreview,
                child: const Text("Ko'rib chiqish"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnRow(int column, List<String> options) {
    final samples = _sampleValues(column);
    final sampleText =
        samples.isEmpty ? '(bo\'sh)' : samples.join(' | ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            ParsedSheet.columnLetter(column),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sampleText,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _roles[column] ?? _rIgnore,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final o in options)
                    DropdownMenuItem<String>(
                      value: o,
                      child: Text(_roleLabel(o), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _phase == _Phase.running
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          if (value == _rIgnore) {
                            _roles.remove(column);
                          } else {
                            _roles[column] = value;
                            // bitta rol faqat bitta ustunda
                            _roles.removeWhere(
                              (c, r) => c != column && r == value,
                            );
                          }
                          _plan = null;
                        });
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final plan = _plan!;
    final byReason = plan.skippedByReason;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ko'rib chiqish natijasi",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Yaratiladi: ${plan.toCreate.length}'),
            Text("O'tkaziladi: ${plan.skipped.length}"),
            if (byReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final entry in byReason.entries)
                Text('${entry.key}: ${entry.value}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
            if (plan.toCreate.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Birinchi namunalar:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final item in plan.toCreate.take(5))
                Text(
                  '${item.sku} - ${item.name}'
                  '${item.defaultShelfLifeDays == null ? '' : ' (${item.defaultShelfLifeDays} kun)'}',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed:
                    (_categoryId == null || plan.toCreate.isEmpty || _phase == _Phase.running)
                        ? null
                        : _runImport,
                icon: const Icon(Icons.upload),
                label: const Text('Import boshlash'),
              ),
            ),
            if (_categoryId == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Import uchun kategoriya tanlang',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final ratio = _total == 0 ? 0.0 : _processed / _total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yuborilyapti: $_processed / $_total'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio),
            const SizedBox(height: 8),
            Text('Yaratildi: $_createdCount, xato: ${_runtimeSkipped.length}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stopRequested = true),
              icon: const Icon(Icons.stop),
              label: const Text("To'xtatish"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport() {
    final planSkipped = _plan?.skipped ?? const <SkippedRow>[];
    final all = [...planSkipped, ..._runtimeSkipped];
    final byReason = <String, int>{};
    for (final s in all) {
      byReason[s.reason] = (byReason[s.reason] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yakuniy hisobot',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Yaratildi: $_createdCount'),
            Text("O'tkazildi: ${all.length}"),
            if (_stopRequested)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Import foydalanuvchi tomonidan to'xtatildi",
                  style: TextStyle(fontSize: 13, color: Colors.orange),
                ),
              ),
            const SizedBox(height: 12),
            for (final entry in byReason.entries)
              Text('${entry.key}: ${entry.value}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            if (all.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('O\'tkazilganlar:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final s in all)
                Text(
                  'Qator ${s.rowNumber} | ${s.sku.isEmpty ? '-' : s.sku} | '
                  '${s.name.isEmpty ? '-' : s.name} | ${s.reason}',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _resetToSetup,
                child: const Text('Yana import qilish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
