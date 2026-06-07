import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';

class ConnectivityState {
  final bool isOnline;
  final bool isSyncing;
  final DateTime? lastSyncTime;

  const ConnectivityState({
    this.isOnline = true,
    this.isSyncing = false,
    this.lastSyncTime,
  });

  ConnectivityState copyWith({
    bool? isOnline,
    bool? isSyncing,
    DateTime? lastSyncTime,
  }) {
    return ConnectivityState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityNotifier() : super(const ConnectivityState()) {
    _init();
  }

  void _init() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any(
        (r) => r != ConnectivityResult.none,
      );
      final wasOffline = !state.isOnline;
      state = state.copyWith(isOnline: hasConnection);

      if (hasConnection && wasOffline) {
        _triggerSync();
      }
    });

    Future.delayed(const Duration(seconds: 5), _checkInitial);
  }

  Future<void> _checkInitial() async {
    final reachable = await ApiService.isServerReachable();
    state = state.copyWith(isOnline: reachable);
  }

  Future<void> _triggerSync() async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true);
    try {
      final storeId = await ApiService.getMyStoreId();
      if (storeId != null) {
        await ProductService.syncPendingChanges(storeId);
        await OrderService.syncPendingOrders();
      }
      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      );
    } catch (_) {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> manualSync() async {
    await _triggerSync();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});
