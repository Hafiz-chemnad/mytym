import 'dart:async';
import '../../chat/services/chat_api.dart';
import '../../orders/services/order_api.dart';
import '../../menu/services/menu_api.dart';

/// Runs the app's single master background loop:
/// - polls the backend for new messages + orders every few seconds
/// - writes results into SQLite via the existing sync methods
/// - notifies the caller (DashboardScreen) so it can bump its
///   ValueNotifier<int> sync trigger and refresh the unread badge
class BackgroundWorker {
  static final BackgroundWorker instance = BackgroundWorker._init();
  BackgroundWorker._init();

  Timer? _masterTimer;

  /// Starts the periodic sync loop for [restaurantId].
  /// [onSynced] is called once immediately, then after every cycle —
  /// use it to bump your sync trigger / refresh badges.
  void start(String restaurantId, Future<void> Function() onSynced) {
    _masterTimer?.cancel();

    // Run once immediately so the UI reflects fresh data right on launch.
    onSynced();

    _masterTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _runSyncCycle(restaurantId);
      await onSynced();
    });
  }

  Future<void> _runSyncCycle(String restaurantId) async {
    // ✅ Modularized: message sync now lives in ChatApi.
    await ChatApi.instance.syncMessagesBackground(restaurantId);

    // ✅ Modularized: order sync now lives in OrderApi.
    await OrderApi.instance.syncOrdersBackground(restaurantId);

    // 🚀 NEW: menu sync from the separate FastAPI/Mongo backend.
    await MenuApi.instance.syncMenuBackground(restaurantId);
  }

  /// Stops the loop. Call this from DashboardScreen.dispose().
  void stop() {
    _masterTimer?.cancel();
    _masterTimer = null;
  }
}