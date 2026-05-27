// lib/services/offline_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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
      version: 2,
      onCreate: (db, v) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createTables(db);
        }
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        price REAL,
        quantity INTEGER,
        description TEXT,
        barcode TEXT,
        image_path TEXT,
        action TEXT DEFAULT 'create',
        created_at TEXT
      )
    ''');

    await db.execute('''
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
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_data TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_stock_changes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        delta INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');
  }

  // ==================== PRODUCT CACHE ====================

  static Future<void> cacheProducts(int storeId, List<dynamic> products) async {
    final database = await db;
    final batch = database.batch();
    for (final p in products) {
      batch.insert('cached_products', {
        'id': p['id'],
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

  static Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final database = await db;
    final rows = await database.query('cached_products', orderBy: 'name ASC');
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

  static Future<void> updateLocalStock(int productId, int delta) async {
    final database = await db;

    // Update cached product quantity
    final product = await getCachedProduct(productId);
    if (product != null) {
      final newQty = (product['quantity'] as int) + delta;
      await database.update(
        'cached_products',
        {'quantity': newQty.clamp(0, 999999)},
        where: 'id = ?',
        whereArgs: [productId],
      );
    }

    // Record change for later sync
    await database.insert('offline_stock_changes', {
      'product_id': productId,
      'delta': delta,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ==================== PENDING PRODUCTS (CREATE/EDIT) ====================

  static Future<int> addPending(Map<String, dynamic> product) async {
    final database = await db;
    return database.insert('pending_products', {
      'name': product['name'],
      'price': product['price'],
      'quantity': product['quantity'],
      'description': product['description'],
      'barcode': product['barcode'],
      'image_path': product['image_path'],
      'action': product['action'] ?? 'create',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getPending() async {
    final database = await db;
    return database.query('pending_products', orderBy: 'id ASC');
  }

  static Future<void> removePending(int id) async {
    final database = await db;
    await database.delete('pending_products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearPending() async {
    final database = await db;
    await database.delete('pending_products');
  }

  static Future<int> pendingCount() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM pending_products',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== OFFLINE ORDERS ====================

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

  // ==================== SYNC ====================

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
  }
}
