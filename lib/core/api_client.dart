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
}