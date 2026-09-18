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
      final response = await _dio.get(
        '/warehouses',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('Sessiya muddati tugagan, qaytadan kiring');
      }
      throw ApiException('Omborlarni yuklashda xatolik');
    }
  }

  Future<List<dynamic>> getCategories(String token) async {
    try {
      final response = await _dio.get(
        '/product-categories',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('Sessiya muddati tugagan, qaytadan kiring');
      }
      throw ApiException('Kategoriyalarni yuklashda xatolik');
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('Sessiya muddati tugagan, qaytadan kiring');
      }
      throw ApiException('Mahsulotlarni yuklashda xatolik');
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('Sessiya muddati tugagan, qaytadan kiring');
      }
      final details = e.response?.data?['details'];
      if (e.response?.statusCode == 400 && details is List && details.isNotEmpty) {
        throw ApiException(details.join(', '));
      }
      throw ApiException('Mahsulotni saqlashda xatolik');
    }
  }
}