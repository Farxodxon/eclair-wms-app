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
      }
    }
    return ApiException(fallback);
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
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
}