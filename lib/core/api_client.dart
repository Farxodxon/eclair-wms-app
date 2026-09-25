import 'package:dio/dio.dart';
import 'package:wms_app/core/config.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final Dio _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  ApiException _handleError(
    DioException e, {
    String fallback = 'Serverga ulanib bolmadi',
  }) {
    if (e.response?.statusCode == 401) {
      return ApiException('Sessiya muddati tugagan, qaytadan kiring');
    }
    if (e.response?.statusCode == 403) {
      return ApiException("Bu amal uchun ruxsat yo'q");
    }
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      final details = data['details'];
      switch (error) {
        case 'insufficient_quantity':
          final available = data['available'];
          if (available != null) {
            return ApiException('Yetarli miqdor yo\'q, mavjud: $available');
          }
          return ApiException('Yetarli miqdor yo\'q');
        case 'note_required':
          return ApiException('Izoh majburiy');
        case 'invalid_request':
          if (details is List && details.isNotEmpty) {
            return ApiException(details.join(', '));
          }
          return ApiException('Ma\'lumotlar noto\'g\'ri');
        case 'invalid_attributes':
          if (details is List && details.isNotEmpty) {
            return ApiException(details.join(', '));
          }
          return ApiException('Atributlar noto\'g\'ri');
        case 'location_already_exists':
          return ApiException('Bunday joylashuv kodi allaqachon mavjud');
        case 'barcode_already_exists':
          return ApiException('Bunday shtrix-kodli konteyner mavjud');
        case 'sku_already_exists':
          return ApiException('Bunday SKU allaqachon mavjud');
        case 'invalid_transition':
          return ApiException("Bu partiya bu holatga o'tkazilmaydi");
      }
    }
    return ApiException(fallback);
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Options _authBytesOptions(String token) {
    return Options(
      headers: {'Authorization': 'Bearer $token'},
      responseType: ResponseType.bytes,
    );
  }

  Future<List<int>> getStockReportBytes(String token, {int? warehouseId}) async {
    try {
      final query = <String, dynamic>{};
      if (warehouseId != null) query['warehouse_id'] = warehouseId;
      final response = await _dio.get(
        '/reports/stock.xlsx',
        queryParameters: query.isEmpty ? null : query,
        options: _authBytesOptions(token),
      );
      return response.data as List<int>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: "Qoldiq hisobotini yuklashda xatolik");
    }
  }

  Future<List<int>> getTransactionsReportBytes(
    String token, {
    required DateTime from,
    required DateTime to,
    int? warehouseId,
  }) async {
    try {
      final query = <String, dynamic>{
        'from': _isoDate(from),
        'to': _isoDate(to),
      };
      if (warehouseId != null) query['warehouse_id'] = warehouseId;
      final response = await _dio.get(
        '/reports/transactions.xlsx',
        queryParameters: query,
        options: _authBytesOptions(token),
      );
      return response.data as List<int>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: "Harakatlar hisobotini yuklashda xatolik");
    }
  }

  String _isoDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-$month-$day';
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '/login',
        data: {'email': email, 'password': password},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException("Email yoki parol noto'g'ri");
      }
      throw ApiException('Serverga ulanib bolmadi');
    }
  }

  Future<List<dynamic>> getWarehouses(String token) async {
    try {
      final response = await _dio.get('/warehouses', options: _authOptions(token));
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Omborlarni yuklashda xatolik');
    }
  }

  Future<List<dynamic>> getCategories(String token) async {
    try {
      final response = await _dio.get(
        '/product-categories',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Kategoriyalarni yuklashda xatolik');
    }
  }

  Future<List<dynamic>> getProducts(
    String token, {
    int? categoryId,
    String? search,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (categoryId != null) query['category_id'] = categoryId;
      if (search != null && search.isNotEmpty) query['search'] = search;
      final response = await _dio.get(
        '/products',
        queryParameters: query.isEmpty ? null : query,
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Mahsulotlarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> createProduct(
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/products',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Mahsulotni saqlashda xatolik');
    }
  }

  Future<List<dynamic>> getZones(String token, int warehouseId) async {
    try {
      final response = await _dio.get(
        '/warehouses/$warehouseId/zones',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Zonalarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> createZone(
    String token,
    int warehouseId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/warehouses/$warehouseId/zones',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Zonani saqlashda xatolik');
    }
  }

  Future<List<dynamic>> getStorageLocations(
    String token,
    int warehouseId, {
    int? zoneId,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (zoneId != null) query['zone_id'] = zoneId;
      final response = await _dio.get(
        '/warehouses/$warehouseId/storage-locations',
        queryParameters: query.isEmpty ? null : query,
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Joylashuvlarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> createStorageLocation(
    String token,
    int warehouseId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/warehouses/$warehouseId/storage-locations',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Joylashuvni saqlashda xatolik');
    }
  }

  Future<List<dynamic>> getBatches(String token, int productId) async {
    try {
      final response = await _dio.get(
        '/products/$productId/batches',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Partiyalarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> createBatch(
    String token,
    int productId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/products/$productId/batches',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Partiyani saqlashda xatolik');
    }
  }

  Future<List<dynamic>> getBatchContainers(String token, int batchId) async {
    try {
      final response = await _dio.get(
        '/batches/$batchId/containers',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Konteynerlarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> createBatchContainer(
    String token,
    int batchId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/batches/$batchId/containers',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Konteynerni saqlashda xatolik');
    }
  }

  Future<List<dynamic>> getProductLocations(String token, int productId) async {
    try {
      final response = await _dio.get(
        '/products/$productId/locations',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Joylashuvlarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>?> getContainerByBarcode(
    String token,
    String barcode,
  ) async {
    try {
      final response = await _dio.get(
        '/containers/barcode/$barcode',
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleError(e, fallback: 'Konteynerni qidirishda xatolik');
    }
  }

  Future<Map<String, dynamic>?> getProductByBarcode(
    String token,
    String barcode,
  ) async {
    try {
      final response = await _dio.get(
        '/products/barcode/$barcode',
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleError(e, fallback: 'Mahsulotni qidirishda xatolik');
    }
  }

  Future<Map<String, dynamic>> inventoryOut(
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/inventory/out',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Chiqarishda xatolik');
    }
  }

  Future<Map<String, dynamic>> inventoryTransfer(
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/inventory/transfer',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Ko\'chirishda xatolik');
    }
  }

  Future<Map<String, dynamic>> inventoryAdjustment(
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '/inventory/adjustment',
        data: body,
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Tuzatishda xatolik');
    }
  }

  Future<List<dynamic>> getInventoryTransactions(
    String token, {
    int? batchContainerId,
    int? locationId,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (batchContainerId != null) query['batch_container_id'] = batchContainerId;
      if (locationId != null) query['location_id'] = locationId;
      final response = await _dio.get(
        '/inventory/transactions',
        queryParameters: query.isEmpty ? null : query,
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Harakatlar tarixini yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> getExpiringBatches(
    String token, {
    int days = 30,
  }) async {
    try {
      final response = await _dio.get(
        '/alerts/expiring-batches',
        queryParameters: {'days': days},
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Ogohlantirishlarni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> getAlertsSummary(String token) async {
    try {
      final response = await _dio.get(
        '/alerts/summary',
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(
        e,
        fallback: "Ogohlantirishlar yig'indisini yuklashda xatolik",
      );
    }
  }

  Future<List<dynamic>> getQualityPending(String token) async {
    try {
      final response = await _dio.get(
        '/quality/pending',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Navbatni yuklashda xatolik');
    }
  }

  Future<Map<String, dynamic>> setQualityStatus(
    String token,
    int batchId,
    String status,
    String note,
  ) async {
    try {
      final response = await _dio.post(
        '/batches/$batchId/quality-status',
        data: {'status': status, 'note': note},
        options: _authOptions(token),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Holatni yangilashda xatolik');
    }
  }

  Future<List<dynamic>> getQualityHistory(String token, int batchId) async {
    try {
      final response = await _dio.get(
        '/batches/$batchId/quality-history',
        options: _authOptions(token),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e, fallback: 'Tarixni yuklashda xatolik');
    }
  }
}