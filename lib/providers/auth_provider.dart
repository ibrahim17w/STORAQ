import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/prefs_service.dart';

class AuthState {
  final User? user;
  final bool isGuest;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  const AuthState({
    this.user,
    this.isGuest = false,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    bool? isGuest,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isGuest: isGuest ?? this.isGuest,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isLoading: true));

  Future<void> checkAuth() async {
    try {
      final prefs = await PrefsService.instance;
      final hasToken = prefs.getString('token') != null;
      final isGuest = prefs.getBool('is_guest') ?? false;
      state = state.copyWith(
        isAuthenticated: hasToken || isGuest,
        isGuest: isGuest,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, isAuthenticated: false);
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.login(email: email, password: password);
      state = state.copyWith(
        isAuthenticated: true,
        isGuest: false,
        isLoading: false,
      );
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    Map<String, dynamic>? store,
    String preferredLanguage = 'en',
    String? turnstileToken,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.register(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        role: role,
        store: store,
        preferredLanguage: preferredLanguage,
        turnstileToken: turnstileToken,
      );
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> guestLogin() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.guestLogin();
      state = state.copyWith(
        isAuthenticated: true,
        isGuest: true,
        isLoading: false,
      );
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> logout() async {
    await AuthService.logout();
    state = const AuthState();
  }

  Future<void> loadCurrentUser() async {
    try {
      final user = await AuthService.getCurrentUser();
      state = state.copyWith(user: user);
    } catch (_) {}
  }

  Future<User> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    final user = await AuthService.updateProfile(
      fullName: fullName,
      phone: phone,
    );
    state = state.copyWith(user: user);
    return user;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier();
  Future.microtask(notifier.checkAuth);
  return notifier;
});
