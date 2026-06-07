// lib/services/offline_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'store_catalog_service.dart';
import 'desktop_db_init.dart';

class OfflineService {
  static void _notifyCatalogChanged() {
    StoreCatalogService.instance.notifyChanged();
  }
  // CRITICAL FIX: Use a single Future to prevent race condition where multiple
  // callers simultaneously trigger _init(), causing SQLite file lock on Windows.
  static Future<Database>? _dbFuture;
  static Future<Database> get db async {
    _dbFuture ??= _init();
    return await _dbFuture!;
  }

  static Future<Database> _init() async {
    await DesktopDbInit.ensureInitialized();
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'storaq.db');
    return openDatabase(
      path,
      version: 15,
      onCreate: (db, v) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createTables(db);
        }
        if (oldV < 3) {
          await _migrateV3(db);
        }
        if (oldV < 4) {
          await _migrateV4(db);
        }
        if (oldV < 5) {
          await _migrateV5(db);
        }
        if (oldV < 6) {
          await _migrateV6(db);
        }
        if (oldV < 7) {
          await _migrateV7(db);
        }
        if (oldV < 8) {
          await _migrateV8(db);
        }
        if (oldV < 9) {
          await _migrateV9(db);
        }
        if (oldV < 10) {
          await _migrateV10(db);
        }
        if (oldV < 11) {
          await _migrateV11(db);
        }
        if (oldV < 12) {
          await _migrateV12(db);
        }
        if (oldV < 13) {
          await _migrateV13(db);
        }
        if (oldV < 14) {
          await _migrateV14(db);
        }
        if (oldV < 15) {
          await _migrateV15(db);
        }
      },
    );
  }

  // Adds the converted display price columns to the product cache so the
  // checkout and receipt screens can show prices in the store's display
  // currency without recomputing them client-side.
  static Future<void> _migrateV14(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE cached_products ADD COLUMN display_price REAL',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE cached_products ADD COLUMN display_currency TEXT',
      );
    } catch (_) {}
  }

  // Adds marketplace visibility fields to cached products so store UI can
  // accurately reflect online/store-only state while offline.
  static Future<void> _migrateV15(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE cached_products ADD COLUMN is_online INTEGER DEFAULT 1',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE cached_products ADD COLUMN went_online_at TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'UPDATE cached_products SET is_online = COALESCE(is_online, 1)',
      );
    } catch (_) {}
  }

  static Future<void> _createTables(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS pending_products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        store_id INTEGER,
        name TEXT NOT NULL,
        price REAL,
        quantity INTEGER,
        description TEXT,
        barcode TEXT,
        category_id INTEGER,
        category_ids TEXT,
        image_path TEXT,
        image_paths TEXT,
        action TEXT DEFAULT 'create',
        created_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_products(
        id INTEGER PRIMARY KEY,
        store_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        price REAL,
        quantity INTEGER,
        description TEXT,
        barcode TEXT,
        images TEXT,
        image_url TEXT,
        local_images TEXT,
        category_id INTEGER,
        low_stock_threshold INTEGER DEFAULT 5,
        currency TEXT DEFAULT 'SYP',
        display_price REAL,
        display_currency TEXT,
        is_online INTEGER DEFAULT 1,
        went_online_at TEXT,
        updated_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS pending_orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_data TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS offline_orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number TEXT NOT NULL,
        store_id INTEGER,
        cashier_name TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        items TEXT NOT NULL,
        subtotal REAL,
        discount REAL,
        tax REAL,
        total REAL,
        payment_method TEXT,
        notes TEXT,
        currency TEXT DEFAULT 'SYP',
        created_at TEXT,
        synced INTEGER DEFAULT 0
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_orders(
        id INTEGER PRIMARY KEY,
        receipt_number TEXT,
        store_id INTEGER,
        data TEXT NOT NULL,
        created_at TEXT,
        cached_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS offline_stock_changes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        delta INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS pending_deletes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        store_id INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS sync_metadata(
        store_id INTEGER PRIMARY KEY,
        last_sync_at TEXT,
        pending_count INTEGER DEFAULT 0
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_store(
        id INTEGER PRIMARY KEY,
        data TEXT NOT NULL,
        cached_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_categories(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        translations TEXT,
        sort_order INTEGER DEFAULT 0,
        parent_id INTEGER,
        cached_at TEXT
      )
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS product_id_map(
        pending_row_id INTEGER PRIMARY KEY,
        server_id INTEGER NOT NULL,
        barcode TEXT,
        store_id INTEGER,
        mapped_at TEXT
      )
    """);
  }

  static Future<void> _migrateV3(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN store_id INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN image_paths TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN category_id INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN category_ids TEXT',
      );
    } catch (_) {}
    await db.execute("""
      CREATE TABLE IF NOT EXISTS pending_deletes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        store_id INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS sync_metadata(
        store_id INTEGER PRIMARY KEY,
        last_sync_at TEXT,
        pending_count INTEGER DEFAULT 0
      )
    """);
  }

  static Future<void> _migrateV4(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_store(
        id INTEGER PRIMARY KEY,
        data TEXT NOT NULL,
        cached_at TEXT
      )
    """);
  }

  static Future<void> _migrateV5(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_store(
        id INTEGER PRIMARY KEY,
        data TEXT NOT NULL,
        cached_at TEXT
      )
    """);
  }

  static Future<void> _migrateV6(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_categories(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        translations TEXT,
        sort_order INTEGER DEFAULT 0,
        parent_id INTEGER,
        cached_at TEXT
      )
    """);
  }

  static Future<void> _migrateV7(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS offline_orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number TEXT NOT NULL,
        store_id INTEGER,
        cashier_name TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        items TEXT NOT NULL,
        subtotal REAL,
        discount REAL,
        tax REAL,
        total REAL,
        payment_method TEXT,
        notes TEXT,
        currency TEXT DEFAULT 'SYP',
        created_at TEXT
      )
    """);
  }

  static Future<void> _migrateV8(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN category_id INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE pending_products ADD COLUMN category_ids TEXT',
      );
    } catch (_) {}
  }

  static Future<void> _migrateV9(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE cached_products ADD COLUMN local_images TEXT',
      );
    } catch (_) {}
  }

  static Future<void> _migrateV10(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE offline_orders ADD COLUMN synced INTEGER DEFAULT 0',
      );
    } catch (_) {}
    await db.execute("""
      CREATE TABLE IF NOT EXISTS cached_orders(
        id INTEGER PRIMARY KEY,
        receipt_number TEXT,
        store_id INTEGER,
        data TEXT NOT NULL,
        created_at TEXT,
        cached_at TEXT
      )
    """);
  }

  static Future<void> _migrateV11(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS product_id_map(
        pending_row_id INTEGER PRIMARY KEY,
        server_id INTEGER NOT NULL,
        barcode TEXT,
        store_id INTEGER,
        mapped_at TEXT
      )
    """);
  }

  static Future<void> _migrateV12(Database db) async {
    await db.delete(
      'offline_orders',
      where: 'synced = ?',
      whereArgs: [1],
    );
  }

  static Future<void> _migrateV13(Database db) async {
    try {
      await db.execute('UPDATE cached_products SET local_images = NULL');
    } catch (_) {}
    await _deleteLegacyImageCacheFiles();
  }

  static final RegExp _legacyImageFilePattern = RegExp(
    r'^prod_\d+_\d+\.[a-zA-Z0-9]+$',
  );

  static String _urlCacheFingerprint(String url) =>
      url.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');

  static int _parseQuantity(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<void> _deleteLegacyImageCacheFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(join(appDir.path, 'cached_images'));
      if (!await imagesDir.exists()) return;
      await for (final entity in imagesDir.list()) {
        if (entity is! File) continue;
        final name = basename(entity.path);
        if (_legacyImageFilePattern.hasMatch(name)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> _purgeProductImageCache(int storeId, int productId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(join(appDir.path, 'cached_images'));
      if (!await imagesDir.exists()) return;
      final legacyPrefix = 'prod_${productId}_';
      final storePrefix = 's${storeId}_p${productId}_';
      await for (final entity in imagesDir.list()) {
        if (entity is! File) continue;
        final name = basename(entity.path);
        if (name.startsWith(legacyPrefix) || name.startsWith(storePrefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ==================== PENDING → SERVER PRODUCT ID MAP ====================

  static bool _syncIdsEqual(dynamic a, dynamic b) {
    if (a == null || b == null) return false;
    return a.toString() == b.toString();
  }

  static Future<void> saveProductIdMapping({
    required int pendingRowId,
    required int serverId,
    String? barcode,
    int? storeId,
  }) async {
    final database = await db;
    await database.insert('product_id_map', {
      'pending_row_id': pendingRowId,
      'server_id': serverId,
      'barcode': barcode,
      'store_id': storeId,
      'mapped_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int?> getServerIdForPendingRow(int pendingRowId) async {
    final database = await db;
    final rows = await database.query(
      'product_id_map',
      where: 'pending_row_id = ?',
      whereArgs: [pendingRowId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['server_id'] as int?;
  }

  static Future<int?> lookupServerIdByBarcode(String barcode) async {
    if (barcode.isEmpty) return null;
    final database = await db;
    final mapped = await database.query(
      'product_id_map',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (mapped.isNotEmpty) {
      return mapped.first['server_id'] as int?;
    }
    final cached = await database.query(
      'cached_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (cached.isNotEmpty) {
      return cached.first['id'] as int?;
    }
    return null;
  }

  /// Resolves pending_* IDs and string IDs to a server product id when possible.
  static Future<int?> resolveServerProductId(
    dynamic productId, {
    String? barcode,
  }) async {
    final pidStr = productId?.toString().trim() ?? '';
    if (pidStr.isEmpty) {
      return barcode != null ? lookupServerIdByBarcode(barcode) : null;
    }

    if (pidStr.startsWith('pending_')) {
      final rowId = int.tryParse(pidStr.replaceFirst('pending_', ''));
      if (rowId != null) {
        final mapped = await getServerIdForPendingRow(rowId);
        if (mapped != null) return mapped;
      }
      return barcode != null ? lookupServerIdByBarcode(barcode) : null;
    }

    int? parsedId;
    if (productId is int) {
      parsedId = productId;
    } else if (productId is double) {
      parsedId = productId.toInt();
    } else {
      parsedId = int.tryParse(pidStr);
      parsedId ??= double.tryParse(pidStr)?.toInt();
    }
    if (parsedId != null && parsedId > 0) return parsedId;

    return barcode != null ? lookupServerIdByBarcode(barcode) : null;
  }

  static Future<Map<String, dynamic>> _remapOrderItemsList(
    List<dynamic> itemsRaw,
  ) async {
    var changed = false;
    final items = <Map<String, dynamic>>[];
    for (final raw in itemsRaw) {
      final map = raw is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final barcode = map['barcode']?.toString();
      final resolved = await resolveServerProductId(
        map['product_id'] ?? map['id'] ?? map['productId'],
        barcode: barcode,
      );
      if (resolved != null) {
        final current = map['product_id'] ?? map['id'];
        if (current?.toString() != resolved.toString()) {
          map['product_id'] = resolved;
          changed = true;
        }
      }
      items.add(map);
    }
    return {'items': items, 'changed': changed};
  }

  /// Rewrites queued receipts so pending_* product ids become real server ids.
  static Future<int> remapAllQueuedOrderItems() async {
    final database = await db;
    var remappedOrders = 0;

    final pendingRows = await database.query(
      'pending_orders',
      where: 'synced = ?',
      whereArgs: [0],
    );
    for (final row in pendingRows) {
      try {
        final orderData =
            jsonDecode(row['order_data'] as String) as Map<String, dynamic>;
        final itemsRaw = orderData['items'] as List<dynamic>? ?? [];
        final result = await _remapOrderItemsList(itemsRaw);
        if (result['changed'] == true) {
          orderData['items'] = result['items'];
          await database.update(
            'pending_orders',
            {'order_data': jsonEncode(orderData)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          remappedOrders++;
        }
      } catch (_) {}
    }

    final offlineRows = await database.query('offline_orders');
    for (final row in offlineRows) {
      try {
        final itemsRaw =
            jsonDecode(row['items'] as String) as List<dynamic>? ?? [];
        final result = await _remapOrderItemsList(itemsRaw);
        if (result['changed'] == true) {
          await database.update(
            'offline_orders',
            {'items': jsonEncode(result['items'])},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      } catch (_) {}
    }

    return remappedOrders;
  }

  // ==================== IMAGE CACHING (NON-BLOCKING) ====================
  // CRITICAL FIX: Replaced all sync file operations (existsSync/lengthSync)
  // with async versions (exists/length) and added event-loop yielding.
  // On Windows, sync file I/O in a tight loop blocks the Dart event loop,
  // causing "Not Responding" freezes.

  static Future<List<String>> _cacheProductImages(
    int storeId,
    int productId,
    List<String> imageUrls,
  ) async {
    await _purgeProductImageCache(storeId, productId);

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(join(appDir.path, 'cached_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final localPaths = <String>[];
    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i].trim();
      if (url.isEmpty || !url.startsWith('http')) continue;

      try {
        final uri = Uri.parse(url);
        final ext = uri.path.split('.').last.split('?').first;
        final safeExt =
            ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext.toLowerCase())
            ? ext
            : 'jpg';
        final urlKey = _urlCacheFingerprint(url);
        final fileName = 's${storeId}_p${productId}_${urlKey}_$i.$safeExt';
        final filePath = join(imagesDir.path, fileName);
        final file = File(filePath);

        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
        }
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0) {
            localPaths.add(filePath);
          }
        }
      } catch (_) {
        // Skip images that fail to download - app stays responsive
      }

      if (i % 2 == 1) {
        await Future.delayed(Duration.zero);
      }
    }
    return localPaths;
  }

  // ==================== OFFLINE ORDERS (RECEIPTS) ====================

  static Future<int> saveOfflineOrder(Map<String, dynamic> orderData) async {
    final database = await db;
    return database.insert('offline_orders', {
      'receipt_number': orderData['receipt_number'],
      'store_id': orderData['store_id'],
      'cashier_name': orderData['cashier_name'],
      'customer_name': orderData['customer_name'],
      'customer_phone': orderData['customer_phone'],
      'items': jsonEncode(orderData['items']),
      'subtotal': orderData['subtotal'],
      'discount': orderData['discount'],
      'tax': orderData['tax'],
      'total': orderData['total'],
      'payment_method': orderData['payment_method'],
      'notes': orderData['notes'],
      'currency': orderData['currency'] ?? 'SYP',
      'created_at': orderData['created_at'] ?? DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getOfflineOrders({
    bool unsyncedOnly = true,
  }) async {
    final database = await db;
    final rows = await database.query(
      'offline_orders',
      where: unsyncedOnly ? 'synced = ?' : null,
      whereArgs: unsyncedOnly ? [0] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      map['items'] = jsonDecode(map['items']);
      map['id'] = 'offline_${map['id']}';
      map['offline'] = true;
      map['pending_sync'] = (map['synced'] as int? ?? 0) == 0;
      return map;
    }).toList();
  }

  static Future<void> markOfflineOrderSynced(String receiptNumber) async {
    await deleteOfflineOrderByReceipt(receiptNumber);
  }

  /// Removes local offline copy after it exists on the server (avoids duplicate history).
  static Future<void> deleteOfflineOrderByReceipt(String receiptNumber) async {
    final database = await db;
    await database.delete(
      'offline_orders',
      where: 'receipt_number = ?',
      whereArgs: [receiptNumber],
    );
  }

  // ==================== CACHED SERVER ORDERS (order history offline) ====================

  static Future<void> cacheOrders(List<dynamic> orders) async {
    if (orders.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    final now = DateTime.now().toIso8601String();
    for (final raw in orders) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      if (id == null) continue;
      final intId = id is int ? id : int.tryParse(id.toString());
      if (intId == null) continue;
      batch.insert('cached_orders', {
        'id': intId,
        'receipt_number': raw['receipt_number']?.toString(),
        'store_id': raw['store_id'],
        'data': jsonEncode(raw),
        'created_at': raw['created_at']?.toString() ?? now,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedOrders({
    int limit = 200,
    int offset = 0,
  }) async {
    final database = await db;
    final rows = await database.query(
      'cached_orders',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) {
      try {
        return jsonDecode(r['data'] as String) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((m) => m.isNotEmpty).toList();
  }

  // ==================== CATEGORIES CACHE ====================
  static Future<void> cacheCategories(List<dynamic> categories) async {
    final database = await db;
    final batch = database.batch();
    for (final cat in categories) {
      if (cat is! Map<String, dynamic>) continue;
      final id = cat['id'];
      if (id == null) continue;
      batch.insert('cached_categories', {
        'id': id is int ? id : int.tryParse(id.toString()) ?? 0,
        'name': cat['name']?.toString() ?? 'Unknown',
        'icon': cat['icon']?.toString(),
        'translations': cat['translations'] != null
            ? jsonEncode(cat['translations'])
            : null,
        'sort_order': cat['sort_order'] ?? 0,
        'parent_id': cat['parent_id'],
        'cached_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedCategories() async {
    final database = await db;
    final rows = await database.query(
      'cached_categories',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      if (map['translations'] != null) {
        try {
          map['translations'] = jsonDecode(map['translations']);
        } catch (_) {}
      }
      return map;
    }).toList();
  }

  // ==================== STORE CACHE ====================
  static Future<void> cacheStore(Map<String, dynamic> store) async {
    final database = await db;
    final id = store['id'];
    if (id == null) return;
    await database.insert('cached_store', {
      'id': id is int ? id : int.tryParse(id.toString()) ?? 0,
      'data': jsonEncode(store),
      'cached_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> clearSessionCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user');
  }

  static Future<Map<String, dynamic>?> getCachedStore({int? storeId}) async {
    final database = await db;
    if (storeId != null) {
      final rows = await database.query(
        'cached_store',
        where: 'id = ?',
        whereArgs: [storeId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        try {
          return jsonDecode(rows.first['data'] as String)
              as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      }
    }
    final rows = await database.query('cached_store', limit: 1);
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> getCachedStoreId() async {
    final store = await getCachedStore();
    return store?['id'] as int?;
  }

  // ==================== CLEAR CACHED PRODUCTS ====================

  static Future<void> clearCachedProducts(int storeId) async {
    final database = await db;
    await database.delete(
      'cached_products',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    _notifyCatalogChanged();
  }

  // ==================== USER CACHE (SharedPreferences) ====================
  static Future<void> cacheUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_user', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_user');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ==================== PRODUCT CACHE ====================
  // CRITICAL FIX: Limit concurrent image downloads to 3 at a time to
  // prevent Windows file-system contention when many products have images.

  static Future<void> cacheProducts(int storeId, List<dynamic> products) async {
    final database = await db;
    final batch = database.batch();
    for (final p in products) {
      final id = p['id'];
      if (id == null) continue;
      batch.insert('cached_products', {
        'id': id is int ? id : int.tryParse(id.toString()) ?? 0,
        'store_id': storeId,
        'name': p['name'],
        'price': p['price'],
        'quantity': p['quantity'],
        'description': p['description'],
        'barcode': p['barcode'],
        'images': p['images'] != null ? jsonEncode(p['images']) : null,
        'image_url': p['image_url'],
        'category_id': p['category_id'],
        'low_stock_threshold': p['low_stock_threshold'] ?? 5,
        'currency': p['currency'] ?? 'SYP',
        'display_price': p['display_price'],
        'display_currency': p['display_currency'],
        'is_online': p['is_online'] == true ? 1 : 0,
        'went_online_at': p['went_online_at']?.toString(),
        'updated_at': p['updated_at'] ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    _notifyCatalogChanged();

    // Process image downloads with limited concurrency (max 3 parallel)
    final imageFutures = <Future<void>>[];
    for (final p in products) {
      final id = p['id'];
      if (id == null) continue;
      final intId = id is int ? id : int.tryParse(id.toString()) ?? 0;

      List<String> urls = [];
      final images = p['images'];
      if (images is List) {
        urls = images.whereType<String>().where((u) => u.isNotEmpty).toList();
      }
      final imageUrl = p['image_url'];
      if (urls.isEmpty && imageUrl is String && imageUrl.isNotEmpty) {
        urls = [imageUrl];
      }

      if (urls.isNotEmpty) {
        imageFutures.add(() async {
          final localPaths = await _cacheProductImages(storeId, intId, urls);
          try {
            final db = await OfflineService.db;
            await db.update(
              'cached_products',
              {
                'local_images': localPaths.isNotEmpty
                    ? jsonEncode(localPaths)
                    : null,
              },
              where: 'id = ? AND store_id = ?',
              whereArgs: [intId, storeId],
            );
          } catch (_) {}
        }());
        // Limit to 3 concurrent downloads
        if (imageFutures.length >= 3) {
          await Future.wait(imageFutures);
          imageFutures.clear();
        }
      }
    }
    if (imageFutures.isNotEmpty) {
      await Future.wait(imageFutures);
    }
  }

  static Future<List<Map<String, dynamic>>> getCachedProducts({
    int? storeId,
  }) async {
    final database = await db;
    final rows = storeId != null
        ? await database.query(
            'cached_products',
            where: 'store_id = ?',
            whereArgs: [storeId],
            orderBy: 'name ASC',
          )
        : await database.query('cached_products', orderBy: 'name ASC');
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      if (map['images'] != null) {
        try {
          map['images'] = jsonDecode(map['images']);
        } catch (_) {}
      }
      if (map['local_images'] != null) {
        try {
          map['local_images'] = jsonDecode(map['local_images']);
        } catch (_) {}
      }
      if (map['is_online'] is int) {
        map['is_online'] = (map['is_online'] as int) == 1;
      }
      return map;
    }).toList();
  }

  static Future<Map<String, dynamic>?> getCachedProduct(int id) async {
    final database = await db;
    final rows = await database.query(
      'cached_products',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final map = Map<String, dynamic>.from(rows.first);
    if (map['images'] != null) {
      try {
        map['images'] = jsonDecode(map['images']);
      } catch (_) {}
    }
    if (map['local_images'] != null) {
      try {
        map['local_images'] = jsonDecode(map['local_images']);
      } catch (_) {}
    }
    if (map['is_online'] is int) {
      map['is_online'] = (map['is_online'] as int) == 1;
    }
    return map;
  }

  static Future<void> updateCachedProduct(Map<String, dynamic> product) async {
    final database = await db;
    final id = product['id'];
    if (id == null) return;
    final intId = id is int ? id : int.tryParse(id.toString());
    if (intId == null) return;
    await database.update(
      'cached_products',
      {
        'name': product['name'],
        'price': product['price'],
        'quantity': product['quantity'],
        'description': product['description'],
        'barcode': product['barcode'],
        'category_id': product['category_id'],
        'low_stock_threshold': product['low_stock_threshold'] ?? 5,
        'currency': product['currency'] ?? 'SYP',
        'is_online': product['is_online'] == true ? 1 : 0,
        'went_online_at': product['went_online_at']?.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [intId],
    );
    _notifyCatalogChanged();
  }

  static Future<void> removeCachedProduct(int id) async {
    final database = await db;
    final rows = await database.query(
      'cached_products',
      columns: ['store_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final storeId = rows.isNotEmpty ? rows.first['store_id'] as int? : null;
    if (storeId != null) {
      await _purgeProductImageCache(storeId, id);
    }
    await database.delete('cached_products', where: 'id = ?', whereArgs: [id]);
    _notifyCatalogChanged();
  }

  static Future<void> updateLocalStock(int productId, int delta) async {
    final database = await db;

    final product = await getCachedProduct(productId);
    if (product != null) {
      final newQty = _parseQuantity(product['quantity']) + delta;
      await database.update(
        'cached_products',
        {'quantity': newQty.clamp(0, 999999)},
        where: 'id = ?',
        whereArgs: [productId],
      );
    }

    await database.insert('offline_stock_changes', {
      'product_id': productId,
      'delta': delta,
      'created_at': DateTime.now().toIso8601String(),
    });
    _notifyCatalogChanged();
  }

  static Future<void> adjustCachedStockOnly(int productId, int delta) async {
    final database = await db;
    final product = await getCachedProduct(productId);
    if (product != null) {
      final newQty = _parseQuantity(product['quantity']) + delta;
      await database.update(
        'cached_products',
        {'quantity': newQty.clamp(0, 999999)},
        where: 'id = ?',
        whereArgs: [productId],
      );
      _notifyCatalogChanged();
    }
  }

  /// Sales adjust server stock via order sync — drop queued deltas for those products.
  static Future<void> discardUnsyncedStockChangesForProducts(
    List<int> productIds,
  ) async {
    if (productIds.isEmpty) return;
    final database = await db;
    for (final pid in productIds) {
      await database.delete(
        'offline_stock_changes',
        where: 'product_id = ? AND synced = ?',
        whereArgs: [pid, 0],
      );
    }
  }

  /// Decrements stock after a sale (queues server sync for synced products).
  static Future<void> adjustProductStockForSale(
    dynamic productId,
    int soldQuantity,
  ) async {
    final delta = -soldQuantity.abs();
    if (productId is String && productId.startsWith('pending_')) {
      final pendingId = int.tryParse(productId.replaceFirst('pending_', ''));
      if (pendingId != null) {
        await _adjustPendingRowQuantity(pendingId, delta);
      }
      return;
    }
    final intId = productId is int
        ? productId
        : int.tryParse(productId?.toString() ?? '');
    if (intId != null && intId > 0) {
      await updateLocalStock(intId, delta);
    }
  }

  static Future<void> _adjustPendingRowQuantity(
    int pendingRowId,
    int delta,
  ) async {
    final database = await db;
    final rows = await database.query(
      'pending_products',
      where: 'id = ?',
      whereArgs: [pendingRowId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = rows.first['quantity'];
    final qty = current is int
        ? current
        : int.tryParse(current?.toString() ?? '0') ?? 0;
    await database.update(
      'pending_products',
      {'quantity': (qty + delta).clamp(0, 999999)},
      where: 'id = ?',
      whereArgs: [pendingRowId],
    );
    _notifyCatalogChanged();
  }

  // ==================== PENDING PRODUCTS ====================

  static Future<int> addPending(
    Map<String, dynamic> product,
    int storeId,
  ) async {
    final database = await db;
    final id = await database.insert('pending_products', {
      'store_id': storeId,
      'name': product['name'],
      'price': product['price'],
      'quantity': product['quantity'],
      'description': product['description'],
      'barcode': product['barcode'],
      'category_id': product['category_id'],
      'category_ids': product['category_ids'] != null
          ? (product['category_ids'] is String
              ? product['category_ids']
              : jsonEncode(product['category_ids']))
          : null,
      'image_path': product['image_path'],
      'image_paths': product['image_paths'] != null
          ? jsonEncode(product['image_paths'])
          : null,
      'action': product['action'] ?? 'create',
      'created_at': DateTime.now().toIso8601String(),
    });
    _notifyCatalogChanged();
    return id;
  }

  static Future<int> addPendingUpdate(
    Map<String, dynamic> product,
    int serverId,
    int storeId,
  ) async {
    final database = await db;
    return database.insert('pending_products', {
      'server_id': serverId,
      'store_id': storeId,
      'name': product['name'],
      'price': product['price'],
      'quantity': product['quantity'],
      'description': product['description'],
      'barcode': product['barcode'],
      'image_path': product['image_path'],
      'image_paths': product['image_paths'] != null
          ? jsonEncode(product['image_paths'])
          : null,
      'action': 'update',
      'created_at': DateTime.now().toIso8601String(),
    });
    _notifyCatalogChanged();
  }

  static Future<void> addPendingDelete(int productId, int storeId) async {
    final database = await db;
    await database.insert('pending_deletes', {
      'product_id': productId,
      'store_id': storeId,
      'created_at': DateTime.now().toIso8601String(),
    });
    _notifyCatalogChanged();
  }

  static Future<List<Map<String, dynamic>>> getPendingCreates({
    int? storeId,
  }) async {
    final database = await db;
    if (storeId != null) {
      return database.query(
        'pending_products',
        where:
            "action = ? AND (server_id IS NULL OR server_id = 0) AND store_id = ?",
        whereArgs: ['create', storeId],
        orderBy: 'id ASC',
      );
    }
    return database.query(
      'pending_products',
      where: "action = ? AND (server_id IS NULL OR server_id = 0)",
      whereArgs: ['create'],
      orderBy: 'id ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingUpdates({
    int? storeId,
  }) async {
    final database = await db;
    if (storeId != null) {
      return database.query(
        'pending_products',
        where: "action = ? AND server_id IS NOT NULL AND store_id = ?",
        whereArgs: ['update', storeId],
        orderBy: 'id ASC',
      );
    }
    return database.query(
      'pending_products',
      where: "action = ? AND server_id IS NOT NULL",
      whereArgs: ['update'],
      orderBy: 'id ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingDeletes({
    int? storeId,
  }) async {
    final database = await db;
    if (storeId != null) {
      return database.query(
        'pending_deletes',
        where: 'synced = ? AND store_id = ?',
        whereArgs: [0, storeId],
        orderBy: 'id ASC',
      );
    }
    return database.query(
      'pending_deletes',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getPending() async {
    final database = await db;
    return database.query('pending_products', orderBy: 'id ASC');
  }

  static Future<void> removePending(int id) async {
    final database = await db;
    await database.delete('pending_products', where: 'id = ?', whereArgs: [id]);
    _notifyCatalogChanged();
  }

  static Future<void> clearPendingProduct(int id) async {
    final database = await db;
    await database.delete('pending_products', where: 'id = ?', whereArgs: [id]);
    _notifyCatalogChanged();
  }

  static Future<void> clearPendingDelete(int id) async {
    final database = await db;
    await database.delete('pending_deletes', where: 'id = ?', whereArgs: [id]);
    _notifyCatalogChanged();
  }

  static Future<void> clearPending() async {
    final database = await db;
    await database.delete('pending_products');
    await database.delete('pending_deletes');
    _notifyCatalogChanged();
  }

  static Future<int> pendingCount() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM pending_products',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<int> pendingProductChangeCount() async {
    final database = await db;
    final creates = await database.rawQuery(
      "SELECT COUNT(*) as c FROM pending_products WHERE action='create' OR action='update'",
    );
    final deletes = await database.rawQuery(
      "SELECT COUNT(*) as c FROM pending_deletes WHERE synced=0",
    );
    final stock = await database.rawQuery(
      "SELECT COUNT(*) as c FROM offline_stock_changes WHERE synced=0",
    );
    return (Sqflite.firstIntValue(creates) ?? 0) +
        (Sqflite.firstIntValue(deletes) ?? 0) +
        (Sqflite.firstIntValue(stock) ?? 0);
  }

  static Future<int> totalPendingCount() async {
    final products = await pendingProductChangeCount();
    final orders = await pendingOrderCount();
    return products + orders;
  }

  // ==================== MERGED VIEW (CACHE + PENDING) ====================

  static Future<List<Map<String, dynamic>>> getMergedProducts(
    int storeId,
  ) async {
    final database = await db;

    final cachedRows = await database.query(
      'cached_products',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'name ASC',
    );

    final pendingDeleteIds = <int>{};
    final deleteRows = await database.query(
      'pending_deletes',
      where: 'store_id = ? AND synced = ?',
      whereArgs: [storeId, 0],
    );
    for (final row in deleteRows) {
      pendingDeleteIds.add(row['product_id'] as int);
    }

    final products = <Map<String, dynamic>>[];
    final cachedNames = <String>{};

    for (final row in cachedRows) {
      final id = row['id'];
      if (id is String) continue;
      if (pendingDeleteIds.contains(id)) continue;

      final map = Map<String, dynamic>.from(row);
      if (map['images'] != null) {
        try {
          map['images'] = jsonDecode(map['images']);
        } catch (_) {}
      }
      if (map['local_images'] != null) {
        try {
          map['local_images'] = jsonDecode(map['local_images']);
        } catch (_) {}
      }
      if (map['is_online'] is int) {
        map['is_online'] = (map['is_online'] as int) == 1;
      }
      products.add(map);
      cachedNames.add((map['name'] as String? ?? '').toLowerCase().trim());
    }

    final updateRows = await database.query(
      'pending_products',
      where: "action = 'update' AND server_id IS NOT NULL AND store_id = ?",
      whereArgs: [storeId],
    );
    final updateMap = <int, Map<String, dynamic>>{};
    for (final row in updateRows) {
      updateMap[row['server_id'] as int] = row;
    }

    for (int i = 0; i < products.length; i++) {
      final id = products[i]['id'] as int;
      if (updateMap.containsKey(id)) {
        final pending = updateMap[id]!;
        products[i]['name'] = pending['name'];
        products[i]['price'] = pending['price'];
        products[i]['quantity'] = _parseQuantity(pending['quantity']);
        products[i]['description'] = pending['description'];
        products[i]['barcode'] = pending['barcode'];
        products[i]['currency'] = pending['currency'];
        products[i]['_pendingUpdate'] = true;
        final updateImages = _pendingImagePathsFromRow(pending);
        if (updateImages.isNotEmpty) {
          products[i]['local_images'] = updateImages;
          products[i]['images'] = updateImages;
          products[i]['image_url'] = updateImages.first;
        }
      }
    }

    final createRows = await database.query(
      'pending_products',
      where:
          "action = 'create' AND (server_id IS NULL OR server_id = 0) AND store_id = ?",
      whereArgs: [storeId],
    );
    for (final row in createRows) {
      final map = Map<String, dynamic>.from(row);
      map['id'] = 'pending_${map['id']}';
      map['_pendingCreate'] = true;

      final rawPaths = map['image_paths'];
      List<String> paths = [];
      if (rawPaths is String) {
        try {
          paths = (jsonDecode(rawPaths) as List<dynamic>)
              .whereType<String>()
              .toList();
        } catch (_) {}
      } else if (rawPaths is List) {
        paths = rawPaths.whereType<String>().toList();
      }
      if (paths.isNotEmpty) {
        map['local_images'] = paths;
        map['images'] = paths;
        map['image_url'] = paths.first;
      }

      final pendingName = (map['name'] as String? ?? '').toLowerCase().trim();
      if (pendingName.isNotEmpty && cachedNames.contains(pendingName)) {
        continue;
      }

      products.add(map);
    }

    return products;
  }

  static List<String> _pendingImagePathsFromRow(Map<String, dynamic> row) {
    final paths = <String>[];

    void addPath(dynamic value) {
      if (value is String && value.isNotEmpty) {
        paths.add(value);
      }
    }

    final rawPaths = row['image_paths'];
    if (rawPaths is String) {
      try {
        for (final item in jsonDecode(rawPaths) as List<dynamic>) {
          addPath(item);
        }
      } catch (_) {}
    } else if (rawPaths is List) {
      for (final item in rawPaths) {
        addPath(item);
      }
    }

    addPath(row['image_path']);

    return paths;
  }

  // ==================== PENDING ORDERS (SYNC QUEUE) ====================

  /// Persists receipt locally and queues it for server sync.
  static Future<void> saveOrderForOffline(Map<String, dynamic> orderData) async {
    await saveOfflineOrder(orderData);
    await queueOrder(orderData);
  }

  static Future<int> queueOrder(Map<String, dynamic> orderData) async {
    final database = await db;
    return database.insert('pending_orders', {
      'order_data': jsonEncode(orderData),
      'synced': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final database = await db;
    final rows = await database.query(
      'pending_orders',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      map['order_data'] = jsonDecode(map['order_data']);
      return map;
    }).toList();
  }

  static Future<void> markOrderSynced(int id) async {
    final database = await db;
    await database.update(
      'pending_orders',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  static Future<void> removePendingOrder(int id) async {
    final database = await db;
    await database.delete('pending_orders', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> pendingOrderCount() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM pending_orders WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== STOCK SYNC ====================

  static Future<List<Map<String, dynamic>>> getUnsyncedStockChanges() async {
    final database = await db;
    return database.query(
      'offline_stock_changes',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<void> markStockChangeSynced(int id) async {
    final database = await db;
    await database.update(
      'offline_stock_changes',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearAllSynced() async {
    final database = await db;
    await database.delete(
      'offline_stock_changes',
      where: 'synced = ?',
      whereArgs: [1],
    );
    await database.delete(
      'pending_orders',
      where: 'synced = ?',
      whereArgs: [1],
    );
    await database.delete(
      'pending_deletes',
      where: 'synced = ?',
      whereArgs: [1],
    );
  }

  // ==================== SYNC METADATA ====================

  static Future<void> setLastSync(int storeId) async {
    final database = await db;
    await database.insert('sync_metadata', {
      'store_id': storeId,
      'last_sync_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<DateTime?> getLastSync(int storeId) async {
    final database = await db;
    final rows = await database.query(
      'sync_metadata',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['last_sync_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ==================== IMAGE PATH RESOLUTION ====================
  // CRITICAL FIX: This helper prefers local cached images over remote URLs.
  // UI widgets should call this instead of reading image_url/images directly.
  //
  // ADDITIONAL FIX: Strips file:// prefix from paths so File() constructor
  // works correctly on all platforms (especially Windows where file://C:\...
  // is not a valid native path).

  static bool _isLegacyCollisionImagePath(String path) {
    return _legacyImageFilePattern.hasMatch(basename(path));
  }

  static List<String> getProductImagePaths(Map<String, dynamic> product) {
    final isPendingCreate = product['_pendingCreate'] == true;

    final local = product['local_images'];
    List<String> candidates = [];

    if (local is List && local.isNotEmpty) {
      candidates = local
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .where((p) => !_isLegacyCollisionImagePath(p))
          .toList();
    }

    if (isPendingCreate) {
      if (candidates.isEmpty) {
        final single = product['image_path'];
        if (single is String && single.isNotEmpty) {
          candidates = [single];
        }
      }
      return candidates.map((path) {
        if (path.startsWith('file://')) return path.substring(7);
        return path;
      }).toList();
    }

    if (candidates.isEmpty) {
      final images = product['images'];
      if (images is List && images.isNotEmpty) {
        candidates = images
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .toList();
      }
    }

    if (candidates.isEmpty) {
      final url = product['image_url'];
      if (url is String && url.isNotEmpty) {
        candidates = [url];
      }
    }

    if (candidates.isEmpty) {
      final single = product['image_path'];
      if (single is String && single.isNotEmpty) {
        candidates = [single];
      }
    }

    // CRITICAL FIX: Strip file:// prefix from all paths.
    // The file:// URI scheme is valid for URIs but NOT for dart:io File paths.
    // On Windows, File('file://C:\\Users\\...') fails because the OS
    // doesn't understand the file:// prefix in native file APIs.
    return candidates.map((path) {
      if (path.startsWith('file://')) {
        return path.substring(7);
      }
      return path;
    }).toList();
  }
}
