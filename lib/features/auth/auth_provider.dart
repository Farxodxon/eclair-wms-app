import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';

enum AuthStatus { loggedOut, loading, loggedIn }

class AuthState {
  final AuthStatus status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  const AuthState({
    required this.status,
    this.token,
    this.user,
    this.error,
  });

  String? get role => user?['role'] as String?;

  bool get canAdjust {
    final r = role;
    return r == 'super_admin' || r == 'warehouse_manager';
  }

  bool get canManageQuality => canAdjust;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(status: AuthStatus.loggedOut));

  final ApiClient _api = ApiClient();

  Future<void> login(String email, String password) async {
    state = const AuthState(status: AuthStatus.loading);
    try {
      final data = await _api.login(email, password);
      state = AuthState(
        status: AuthStatus.loggedIn,
        token: data['token'] as String,
        user: data['user'] as Map<String, dynamic>,
      );
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.loggedOut, error: e.message);
    }
  }

  void logout() {
    state = const AuthState(status: AuthStatus.loggedOut);
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());