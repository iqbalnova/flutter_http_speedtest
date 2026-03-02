// lib/services/speed_test_history_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../models/speed_test_history.dart';

class SpeedTestHistoryService {
  static const String _boxName = 'speedTestHistory';

  // Singleton pattern to ensure only one instance
  static final SpeedTestHistoryService _instance =
      SpeedTestHistoryService._internal();
  factory SpeedTestHistoryService() => _instance;
  SpeedTestHistoryService._internal();

  Box<SpeedTestHistory>? _box;
  bool _isInitialized = false;
  bool _isInitializing = false;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize Hive and open the box
  Future<void> init() async {
    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      debugPrint('Init already in progress, waiting...');
      // Wait for current initialization to complete
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    // Already initialized and box is open
    if (_isInitialized && _box != null && _box!.isOpen) {
      debugPrint('SpeedTest history service already initialized');
      return;
    }

    _isInitializing = true;

    try {
      // Initialize Hive for Flutter (safe to call multiple times)
      await Hive.initFlutter();

      // Register adapters if not already registered
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SpeedTestHistoryAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(SpeedTestResultDataAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(NetworkQualityDataAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(ScenarioQualityDataAdapter());
      }
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter(NetworkMetadataDataAdapter());
      }

      // Open the box (or reopen if it was closed)
      if (_box == null || !_box!.isOpen) {
        _box = await Hive.openBox<SpeedTestHistory>(_boxName);
      }

      _isInitialized = true;
      debugPrint('SpeedTest history box opened successfully');
    } catch (e) {
      debugPrint('Error initializing SpeedTest history service: $e');
      _isInitialized = false;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Ensure box is initialized
  Box<SpeedTestHistory> get box {
    if (!_isInitialized || _box == null || !_box!.isOpen) {
      throw Exception(
        'SpeedTest history box is not initialized. Call init() first.',
      );
    }
    return _box!;
  }

  /// Add a new speed test result to history
  /// Usage: await addHistory(result, timestamp: DateTime.now())
  /// Returns true if successful, false otherwise
  Future<bool> addHistory(
    dynamic speedTestResult, {
    DateTime? timestamp,
  }) async {
    // Auto-initialize if not ready
    if (!_isInitialized) {
      try {
        await init();
      } catch (e) {
        debugPrint('Failed to auto-initialize: $e');
        return false;
      }
    }

    try {
      final history = SpeedTestHistory.fromResult(
        speedTestResult,
        customTimestamp: timestamp ?? DateTime.now(),
      );
      await box.add(history);
      debugPrint('Speed test history saved. Total: ${box.length}');
      return true;
    } catch (e) {
      debugPrint('Error adding speed test history: $e');
      return false;
    }
  }

  /// Get all history items sorted by timestamp (newest first)
  List<SpeedTestHistory> getAll() {
    if (!_isInitialized) {
      debugPrint('Service not initialized, returning empty list');
      return [];
    }

    try {
      final items = box.values.toList();
      // Sort by timestamp, newest first
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (e) {
      debugPrint('Error getting all history: $e');
      return [];
    }
  }

  /// Get history items grouped by date
  Map<String, List<SpeedTestHistory>> getGroupedByDate() {
    final all = getAll();
    final Map<String, List<SpeedTestHistory>> grouped = {};

    for (final item in all) {
      final dateKey = _getDateKey(item.timestamp);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(item);
    }

    return grouped;
  }

  String _getDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final testDate = DateTime(date.year, date.month, date.day);

    if (testDate == today) {
      return 'Today';
    } else if (testDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (testDate.isAfter(today.subtract(const Duration(days: 7)))) {
      return 'This Week';
    } else if (testDate.year == today.year && testDate.month == today.month) {
      return 'This Month';
    } else {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[testDate.month - 1]} ${testDate.year}';
    }
  }

  /// Get a specific history item by index
  SpeedTestHistory? getAt(int index) {
    if (!_isInitialized) return null;

    try {
      return box.getAt(index);
    } catch (e) {
      debugPrint('Error getting history at index $index: $e');
      return null;
    }
  }

  /// Delete a specific history item
  Future<void> delete(SpeedTestHistory item) async {
    try {
      await item.delete();
      debugPrint('Speed test history deleted. Remaining: ${box.length}');
    } catch (e) {
      debugPrint('Error deleting history: $e');
      rethrow;
    }
  }

  /// Delete history item at specific index
  Future<void> deleteAt(int index) async {
    try {
      await box.deleteAt(index);
      debugPrint(
        'Speed test history at index $index deleted. Remaining: ${box.length}',
      );
    } catch (e) {
      debugPrint('Error deleting history at index $index: $e');
      rethrow;
    }
  }

  /// Delete all history
  Future<void> deleteAll() async {
    try {
      await box.clear();
      debugPrint('All speed test history deleted');
    } catch (e) {
      debugPrint('Error deleting all history: $e');
      rethrow;
    }
  }

  /// Get total count of history items
  int get count => _isInitialized ? box.length : 0;

  /// Check if history is empty
  bool get isEmpty => _isInitialized ? box.isEmpty : true;

  /// Check if history is not empty
  bool get isNotEmpty => _isInitialized ? box.isNotEmpty : false;

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    if (!_isInitialized) {
      return {
        'total': 0,
        'avgDownload': 0.0,
        'avgUpload': 0.0,
        'avgLatency': 0.0,
        'maxDownload': 0.0,
        'maxUpload': 0.0,
        'minLatency': 0.0,
      };
    }

    final items = box.values.toList();
    if (items.isEmpty) {
      return {
        'total': 0,
        'avgDownload': 0.0,
        'avgUpload': 0.0,
        'avgLatency': 0.0,
        'maxDownload': 0.0,
        'maxUpload': 0.0,
        'minLatency': 0.0,
      };
    }

    final downloads = items
        .where((e) => e.downloadMbps != null)
        .map((e) => e.downloadMbps!)
        .toList();
    final uploads = items
        .where((e) => e.uploadMbps != null)
        .map((e) => e.uploadMbps!)
        .toList();
    final latencies = items
        .where((e) => e.latencyMs != null)
        .map((e) => e.latencyMs!)
        .toList();

    return {
      'total': items.length,
      'avgDownload': downloads.isEmpty
          ? 0.0
          : downloads.reduce((a, b) => a + b) / downloads.length,
      'avgUpload': uploads.isEmpty
          ? 0.0
          : uploads.reduce((a, b) => a + b) / uploads.length,
      'avgLatency': latencies.isEmpty
          ? 0.0
          : latencies.reduce((a, b) => a + b) / latencies.length,
      'maxDownload': downloads.isEmpty
          ? 0.0
          : downloads.reduce((a, b) => a > b ? a : b),
      'maxUpload': uploads.isEmpty
          ? 0.0
          : uploads.reduce((a, b) => a > b ? a : b),
      'minLatency': latencies.isEmpty
          ? 0.0
          : latencies.reduce((a, b) => a < b ? a : b),
    };
  }

  /// Listen to box changes
  Stream<BoxEvent> watch() {
    if (!_isInitialized) {
      return const Stream.empty();
    }
    return box.watch();
  }
}
