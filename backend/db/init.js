//db/init.js
const { pool } = require('../config/database');

// ==================== MIGRATIONS ====================
async function runMigrations() {
  await pool.query(`
    DO $$
    BEGIN
      -- ORDERS: patch all missing columns
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'orders') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='cashier_id') THEN
          ALTER TABLE orders ADD COLUMN cashier_id INTEGER REFERENCES users(id);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='cashier_name') THEN
          ALTER TABLE orders ADD COLUMN cashier_name VARCHAR(100);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='customer_name') THEN
          ALTER TABLE orders ADD COLUMN customer_name VARCHAR(100);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='customer_phone') THEN
          ALTER TABLE orders ADD COLUMN customer_phone VARCHAR(50);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='receipt_number') THEN
          ALTER TABLE orders ADD COLUMN receipt_number VARCHAR(50);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='subtotal') THEN
          ALTER TABLE orders ADD COLUMN subtotal DECIMAL(12,2) NOT NULL DEFAULT 0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='discount') THEN
          ALTER TABLE orders ADD COLUMN discount DECIMAL(12,2) NOT NULL DEFAULT 0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='tax') THEN
          ALTER TABLE orders ADD COLUMN tax DECIMAL(12,2) NOT NULL DEFAULT 0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='total') THEN
          ALTER TABLE orders ADD COLUMN total DECIMAL(12,2) NOT NULL DEFAULT 0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='status') THEN
          ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'completed';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='payment_method') THEN
          ALTER TABLE orders ADD COLUMN payment_method VARCHAR(20) DEFAULT 'cash';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='notes') THEN
          ALTER TABLE orders ADD COLUMN notes TEXT;
        END IF;
      END IF;

      -- ORDER_ITEMS: patch missing product_name
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'order_items') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='product_name') THEN
          ALTER TABLE order_items ADD COLUMN product_name VARCHAR(200);
        END IF;
      END IF;

      -- STORES: patch all missing columns
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stores') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='rating') THEN
          ALTER TABLE stores ADD COLUMN rating DECIMAL(2,1) DEFAULT 5.0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='is_sponsored') THEN
          ALTER TABLE stores ADD COLUMN is_sponsored BOOLEAN DEFAULT FALSE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='sponsorship_tier') THEN
          ALTER TABLE stores ADD COLUMN sponsorship_tier INTEGER DEFAULT 1;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='sponsorship_expires_at') THEN
          ALTER TABLE stores ADD COLUMN sponsorship_expires_at TIMESTAMP;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='city_id') THEN
          ALTER TABLE stores ADD COLUMN city_id VARCHAR(100);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='country_code') THEN
          ALTER TABLE stores ADD COLUMN country_code VARCHAR(2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='lat') THEN
          ALTER TABLE stores ADD COLUMN lat DOUBLE PRECISION;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='lng') THEN
          ALTER TABLE stores ADD COLUMN lng DOUBLE PRECISION;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='image_url') THEN
          ALTER TABLE stores ADD COLUMN image_url TEXT;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='logo_url') THEN
          ALTER TABLE stores ADD COLUMN logo_url TEXT;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='description') THEN
          ALTER TABLE stores ADD COLUMN description TEXT;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='address') THEN
          ALTER TABLE stores ADD COLUMN address TEXT;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='phone') THEN
          ALTER TABLE stores ADD COLUMN phone VARCHAR(50);
        END IF;
      END IF;

      -- PRODUCTS: patch missing columns
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='currency') THEN
          ALTER TABLE products ADD COLUMN currency VARCHAR(10) DEFAULT 'SYP';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='embedding') THEN
          ALTER TABLE products ADD COLUMN embedding vector(512);
        END IF;
      END IF;
    END $$;
  `);
  console.log('✅ Database migrations applied');
}

// ==================== PATCH FOREIGN KEY CONSTRAINTS ====================
async function patchForeignKeyConstraints() {
  try {
    await pool.query(`
      DO $$
      BEGIN
        -- order_items.product_id: SET NULL (preserve order history)
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'order_items_product_id_fkey'
          AND table_name = 'order_items'
        ) THEN
          ALTER TABLE order_items DROP CONSTRAINT order_items_product_id_fkey;
          ALTER TABLE order_items ALTER COLUMN product_id DROP NOT NULL;
          ALTER TABLE order_items ADD CONSTRAINT order_items_product_id_fkey
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
        END IF;

        -- orders.store_id: SET NULL (preserve order history when store deleted)
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'orders_store_id_fkey'
          AND table_name = 'orders'
        ) THEN
          ALTER TABLE orders DROP CONSTRAINT orders_store_id_fkey;
          ALTER TABLE orders ALTER COLUMN store_id DROP NOT NULL;
          ALTER TABLE orders ADD CONSTRAINT orders_store_id_fkey
            FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL;
        END IF;

        -- orders.cashier_id: SET NULL (preserve order history when cashier deleted)
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'orders_cashier_id_fkey'
          AND table_name = 'orders'
        ) THEN
          ALTER TABLE orders DROP CONSTRAINT orders_cashier_id_fkey;
          ALTER TABLE orders ADD CONSTRAINT orders_cashier_id_fkey
            FOREIGN KEY (cashier_id) REFERENCES users(id) ON DELETE SET NULL;
        END IF;

        -- store_staff.user_id: CASCADE (clean up staff entries when user deleted)
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'store_staff_user_id_fkey'
          AND table_name = 'store_staff'
        ) THEN
          ALTER TABLE store_staff DROP CONSTRAINT store_staff_user_id_fkey;
          ALTER TABLE store_staff ADD CONSTRAINT store_staff_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
        END IF;

        -- store_staff.invited_by: SET NULL
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'store_staff_invited_by_fkey'
          AND table_name = 'store_staff'
        ) THEN
          ALTER TABLE store_staff DROP CONSTRAINT store_staff_invited_by_fkey;
          ALTER TABLE store_staff ADD CONSTRAINT store_staff_invited_by_fkey
            FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE SET NULL;
        END IF;
      END $$;
    `);
    console.log('✅ Foreign key constraints patched');
  } catch (err) {
    console.error('FK patch warning (non-critical):', err.message);
  }
}

// ==================== NEW: INVENTORY & CHECKOUT TABLES ====================
async function initInventoryTables() {
  await runMigrations(); // <-- PATCH FIRST

  await pool.query(`
    CREATE TABLE IF NOT EXISTS categories (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL UNIQUE,
      parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      icon VARCHAR(50),
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS products (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      name VARCHAR(200) NOT NULL,
      price DECIMAL(12,2) NOT NULL DEFAULT 0,
      quantity INTEGER NOT NULL DEFAULT 0,
      description TEXT,
      barcode VARCHAR(50) UNIQUE,
      category_id INTEGER REFERENCES categories(id),
      images JSONB DEFAULT '[]',
      image_url TEXT,
      low_stock_threshold INTEGER DEFAULT 5,
      view_count INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='barcode') THEN
        ALTER TABLE products ADD COLUMN barcode VARCHAR(50) UNIQUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='category_id') THEN
        ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES categories(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='images') THEN
        ALTER TABLE products ADD COLUMN images JSONB DEFAULT '[]';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='low_stock_threshold') THEN
        ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER DEFAULT 5;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='view_count') THEN
        ALTER TABLE products ADD COLUMN view_count INTEGER DEFAULT 0;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='updated_at') THEN
        ALTER TABLE products ADD COLUMN updated_at TIMESTAMP DEFAULT NOW();
      END IF;
    END $$;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      store_id INTEGER REFERENCES stores(id) ON DELETE SET NULL,
      cashier_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      cashier_name VARCHAR(100),
      customer_name VARCHAR(100),
      customer_phone VARCHAR(50),
      receipt_number VARCHAR(50) NOT NULL UNIQUE,
      subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
      discount DECIMAL(12,2) NOT NULL DEFAULT 0,
      tax DECIMAL(12,2) NOT NULL DEFAULT 0,
      total DECIMAL(12,2) NOT NULL DEFAULT 0,
      status VARCHAR(20) DEFAULT 'completed',
      payment_method VARCHAR(20) DEFAULT 'cash',
      notes TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS order_items (
      id SERIAL PRIMARY KEY,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
      product_name VARCHAR(200),
      quantity INTEGER NOT NULL,
      unit_price DECIMAL(12,2) NOT NULL,
      total_price DECIMAL(12,2) NOT NULL,
      barcode VARCHAR(50)
    );
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='categories' AND column_name='translations') THEN
        ALTER TABLE categories ADD COLUMN translations JSONB DEFAULT '{}';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='categories' AND column_name='sort_order') THEN
        ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0;
      END IF;
    END $$;
  `);

  const categories = [
    {
      name: 'General',
      icon: 'category',
      translations: {
        ar: 'عام', en: 'General', fr: 'Général', es: 'General', tr: 'Genel',
        ur: 'عام', hi: 'सामान्य', bn: 'সাধারণ', ru: 'Общее', zh: '一般'
      }
    },
    {
      name: 'Food & Beverages',
      icon: 'restaurant',
      translations: {
        ar: 'الطعام والمشروبات', en: 'Food & Beverages', fr: 'Alimentation',
        es: 'Alimentos y Bebidas', tr: 'Yiyecek ve İçecek', ur: 'کھانا اور مشروبات',
        hi: 'खाद्य और पेय', bn: 'খাদ্য ও পানীয়', ru: 'Еда и напитки', zh: '食品与饮料'
      }
    },
    {
      name: 'Clothing & Apparel',
      icon: 'checkroom',
      translations: {
        ar: 'الملابس والأزياء', en: 'Clothing & Apparel', fr: 'Vêtements',
        es: 'Ropa y Vestimenta', tr: 'Giyim', ur: 'کپڑے اور لباس',
        hi: 'वस्त्र और पहनावा', bn: 'পোশাক ও পার্শ্ববর্তী', ru: 'Одежда', zh: '服装与服饰'
      }
    },
    {
      name: 'Electronics',
      icon: 'devices',
      translations: {
        ar: 'الإلكترونيات', en: 'Electronics', fr: 'Électronique',
        es: 'Electrónica', tr: 'Elektronik', ur: 'الیکٹرانکس',
        hi: 'इलेक्ट्रॉनिक्स', bn: 'ইলেকট্রনিক্স', ru: 'Электроника', zh: '电子产品'
      }
    },
    {
      name: 'Home & Garden',
      icon: 'home',
      translations: {
        ar: 'المنزل والحديقة', en: 'Home & Garden', fr: 'Maison et Jardin',
        es: 'Hogar y Jardín', tr: 'Ev ve Bahçe', ur: 'گھر اور باغ',
        hi: 'घर और बगीचा', bn: 'বাড়ি ও বাগান', ru: 'Дом и сад', zh: '家居与园艺'
      }
    },
    {
      name: 'Health & Beauty',
      icon: 'healing',
      translations: {
        ar: 'الصحة والجمال', en: 'Health & Beauty', fr: 'Santé et Beauté',
        es: 'Salud y Belleza', tr: 'Sağlık ve Güzellik', ur: 'صحت اور خوبصورتی',
        hi: 'स्वास्थ्य और सौंदर्य', bn: 'স্বাস্থ্য ও সৌন্দর্য', ru: 'Здоровье и красота', zh: '健康与美容'
      }
    },
    {
      name: 'Toys & Games',
      icon: 'toys',
      translations: {
        ar: 'الألعاب', en: 'Toys & Games', fr: 'Jouets et Jeux',
        es: 'Juguetes y Juegos', tr: 'Oyuncaklar ve Oyunlar', ur: 'کھلونے اور کھیل',
        hi: 'खिलौने और खेल', bn: 'খেলনা ও খেলা', ru: 'Игрушки и игры', zh: '玩具与游戏'
      }
    },
    {
      name: 'Automotive',
      icon: 'directions_car',
      translations: {
        ar: 'السيارات', en: 'Automotive', fr: 'Automobile',
        es: 'Automotriz', tr: 'Otomotiv', ur: 'آٹوموٹو',
        hi: 'ऑटोमोटिव', bn: 'অটোমোবাইল', ru: 'Автомобили', zh: '汽车用品'
      }
    },
    {
      name: 'Books & Stationery',
      icon: 'menu_book',
      translations: {
        ar: 'الكتب والقرطاسية', en: 'Books & Stationery', fr: 'Livres et Papeterie',
        es: 'Libros y Papelería', tr: 'Kitaplar ve Kırtasiye', ur: 'کتابیں اور سٹیشنری',
        hi: 'पुस्तकें और स्टेशनरी', bn: 'বই ও স্টেশনারি', ru: 'Книги и канцтовары', zh: '书籍与文具'
      }
    },
    {
      name: 'Sports & Outdoors',
      icon: 'sports',
      translations: {
        ar: 'الرياضة والأنشطة الخارجية', en: 'Sports & Outdoors', fr: 'Sports et Plein air',
        es: 'Deportes y Aire Libre', tr: 'Spor ve Outdoor', ur: 'کھیل اور بیرونی سرگرمیاں',
        hi: 'खेल और बाहरी गतिविधियाँ', bn: 'খেলাধুলা ও বাহিরে', ru: 'Спорт и отдых', zh: '运动与户外'
      }
    },
  ];

  for (let i = 0; i < categories.length; i++) {
    const cat = categories[i];
    await pool.query(
      `INSERT INTO categories (name, icon, translations, sort_order)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (name) DO UPDATE SET
         icon = EXCLUDED.icon,
         translations = EXCLUDED.translations,
         sort_order = EXCLUDED.sort_order`,
      [cat.name, cat.icon, JSON.stringify(cat.translations), i]
    );
  }

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_orders_store ON orders(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_orders_receipt ON orders(receipt_number);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);`);

  await patchForeignKeyConstraints();
  console.log('✅ Inventory tables initialized');
}

// ==================== AUTH TABLES ====================
async function initAuthTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS failed_logins (
      email VARCHAR(255) PRIMARY KEY,
      count INTEGER DEFAULT 0,
      locked_until TIMESTAMP,
      last_attempt TIMESTAMP
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS verification_codes (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) NOT NULL,
      type VARCHAR(50) NOT NULL,
      code_hash VARCHAR(255) NOT NULL,
      expires_at TIMESTAMP NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      attempts INTEGER DEFAULT 0,
      used BOOLEAN DEFAULT FALSE,
      verified_at TIMESTAMP,
      invalidated_at TIMESTAMP
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_views (
      id SERIAL PRIMARY KEY,
      product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
      user_id VARCHAR(100),
      viewed_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS search_queries (
      id SERIAL PRIMARY KEY,
      query VARCHAR(200),
      user_id VARCHAR(100),
      searched_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_images (
      id SERIAL PRIMARY KEY,
      product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
      image_url TEXT NOT NULL,
      sort_order INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_categories (
      product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
      category_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
      PRIMARY KEY (product_id, category_id)
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS receipt_settings (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL,
      footer_message VARCHAR(255) DEFAULT 'Thank you for your purchase!',
      show_logo BOOLEAN DEFAULT TRUE,
      show_barcode BOOLEAN DEFAULT TRUE,
      currency_symbol VARCHAR(10) DEFAULT 'SYP',
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      CONSTRAINT fk_receipt_settings_store FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
    );
  `);

  // ==================== NEW: STORE STAFF ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS store_staff (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      can_manage_inventory BOOLEAN DEFAULT FALSE,
      status VARCHAR(20) DEFAULT 'pending',
      invited_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
      invited_at TIMESTAMP DEFAULT NOW(),
      responded_at TIMESTAMP,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(store_id, user_id)
    );
  `);

  // Migration: add status column if table already exists without it
  await pool.query(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'store_staff') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='store_staff' AND column_name='status') THEN
          ALTER TABLE store_staff ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='store_staff' AND column_name='invited_by') THEN
          ALTER TABLE store_staff ADD COLUMN invited_by INTEGER REFERENCES users(id) ON DELETE SET NULL;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='store_staff' AND column_name='invited_at') THEN
          ALTER TABLE store_staff ADD COLUMN invited_at TIMESTAMP DEFAULT NOW();
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='store_staff' AND column_name='responded_at') THEN
          ALTER TABLE store_staff ADD COLUMN responded_at TIMESTAMP;
        END IF;
        -- Default existing rows to accepted so they don't break
        UPDATE store_staff SET status = 'accepted' WHERE status IS NULL OR status = '';
      END IF;
    END $$;
  `);
  // ==================== FAVORITES ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS favorites (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, product_id)
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorites_user ON favorites(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorites_product ON favorites(product_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_user ON store_staff(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_store ON store_staff(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_status ON store_staff(status);`);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_verification_codes_email_created ON verification_codes(email, created_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_views_user ON product_views(user_id, viewed_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_search_queries_user ON search_queries(user_id, searched_at);`);
  
  await patchForeignKeyConstraints();
  console.log('✅ Auth & auxiliary tables initialized');
}

module.exports = { initInventoryTables, initAuthTables };