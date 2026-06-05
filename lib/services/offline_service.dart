// lib/services/offline_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineService {
  static Database? _db;
  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'market_bridge.db');
    return openDatabase(
      path,
      version: 8, // Bumped for offline_orders table
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
      },
    );
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
        category_id INTEGER,
        low_stock_threshold INTEGER DEFAULT 5,
        currency TEXT DEFAULT 'SYP',
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

    // NEW: offline_orders table for completed offline orders (receipts)
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
    });
  }

  static Future<List<Map<String, dynamic>>> getOfflineOrders() async {
    final database = await db;
    final rows = await database.query(
      'offline_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      map['items'] = jsonDecode(map['items']);
      map['id'] = 'offline_${map['id']}';
      map['offline'] = true;
      return map;
    }).toList();
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

  static Future<Map<String, dynamic>?> getCachedStore() async {
    final database = await db;
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
        'updated_at': p['updated_at'] ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
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
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [intId],
    );
  }

  static Future<void> removeCachedProduct(int id) async {
    final database = await db;
    await database.delete('cached_products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateLocalStock(int productId, int delta) async {
    final database = await db;

    final product = await getCachedProduct(productId);
    if (product != null) {
      final newQty = (product['quantity'] as int? ?? 0) + delta;
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
  }

  /// Updates cached stock WITHOUT creating a sync record.
  /// Use this for offline checkout so stock changes are not double-applied on sync.
  static Future<void> adjustCachedStockOnly(int productId, int delta) async {
    final database = await db;
    final product = await getCachedProduct(productId);
    if (product != null) {
      final newQty = (product['quantity'] as int? ?? 0) + delta;
      await database.update(
        'cached_products',
        {'quantity': newQty.clamp(0, 999999)},
        where: 'id = ?',
        whereArgs: [productId],
      );
    }
  }

  // ==================== PENDING PRODUCTS ====================

  static Future<int> addPending(
    Map<String, dynamic> product,
    int storeId,
  ) async {
    final database = await db;
    return database.insert('pending_products', {
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
      'action': product['action'] ?? 'create',
      'created_at': DateTime.now().toIso8601String(),
    });
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
  }

  static Future<void> addPendingDelete(int productId, int storeId) async {
    final database = await db;
    await database.insert('pending_deletes', {
      'product_id': productId,
      'store_id': storeId,
      'created_at': DateTime.now().toIso8601String(),
    });
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
  }

  static Future<void> clearPendingProduct(int id) async {
    final database = await db;
    await database.delete('pending_products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearPendingDelete(int id) async {
    final database = await db;
    await database.delete('pending_deletes', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearPending() async {
    final database = await db;
    await database.delete('pending_products');
    await database.delete('pending_deletes');
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

    for (final row in cachedRows) {
      final id = row['id'] as int;
      if (pendingDeleteIds.contains(id)) continue;

      // Skip orphaned temp cached products from old bug.
      // Temp offline-created products had local file paths in image_url/images
      // instead of HTTP URLs. After sync they remain as ghosts with different IDs.
      final imageUrl = row['image_url'] as String?;
      if (imageUrl != null &&
          imageUrl.isNotEmpty &&
          !imageUrl.startsWith('http')) {
        continue;
      }
      final imagesJson = row['images'] as String?;
      if (imagesJson != null && imagesJson.isNotEmpty) {
        try {
          final imagesList = jsonDecode(imagesJson) as List<dynamic>;
          if (imagesList.any(
            (img) => img is String && img.isNotEmpty && !img.startsWith('http'),
          )) {
            continue;
          }
        } catch (_) {}
      }

      final map = Map<String, dynamic>.from(row);
      if (map['images'] != null) {
        try {
          map['images'] = jsonDecode(map['images']);
        } catch (_) {}
      }
      products.add(map);
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
        products[i]['quantity'] = pending['quantity'];
        products[i]['description'] = pending['description'];
        products[i]['barcode'] = pending['barcode'];
        products[i]['currency'] = pending['currency'];
        products[i]['_pendingUpdate'] = true;
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
      products.add(map);
    }

    return products;
  }

  // ==================== PENDING ORDERS (SYNC QUEUE) ====================

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
}
