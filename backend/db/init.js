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
        -- CURRENCY DISPLAY: converted total snapshot
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='display_subtotal') THEN
          ALTER TABLE orders ADD COLUMN display_subtotal DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='display_discount') THEN
          ALTER TABLE orders ADD COLUMN display_discount DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='display_tax') THEN
          ALTER TABLE orders ADD COLUMN display_tax DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='display_total') THEN
          ALTER TABLE orders ADD COLUMN display_total DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='display_currency') THEN
          ALTER TABLE orders ADD COLUMN display_currency VARCHAR(10);
        END IF;
      END IF;

      -- ORDER_ITEMS: patch missing product_name
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'order_items') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='product_name') THEN
          ALTER TABLE order_items ADD COLUMN product_name VARCHAR(200);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='currency') THEN
          ALTER TABLE order_items ADD COLUMN currency VARCHAR(10);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='display_price') THEN
          ALTER TABLE order_items ADD COLUMN display_price DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='display_currency') THEN
          ALTER TABLE order_items ADD COLUMN display_currency VARCHAR(10);
        END IF;
      END IF;

      -- USERS: profile avatar
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='avatar_url') THEN
          ALTER TABLE users ADD COLUMN avatar_url TEXT;
        END IF;
      END IF;

      -- STORES: patch all missing columns
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stores') THEN
        -- is_active: required by sponsored products / reviews / chat queries.
        -- Without this column, every SELECT that filters on s.is_active
        -- (e.g. /api/products/sponsored, /api/stores) throws and the route
        -- returns 500 — the marketplace looks empty even though data exists.
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='is_active') THEN
          ALTER TABLE stores ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
        END IF;
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
        -- CURRENCY DISPLAY: store-level conversion settings
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='display_currency') THEN
          ALTER TABLE stores ADD COLUMN display_currency VARCHAR(10);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='show_both_prices') THEN
          ALTER TABLE stores ADD COLUMN show_both_prices BOOLEAN DEFAULT FALSE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='exchange_rates') THEN
          ALTER TABLE stores ADD COLUMN exchange_rates JSONB DEFAULT '[]';
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
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='display_price') THEN
          ALTER TABLE products ADD COLUMN display_price DECIMAL(12,2);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='display_currency') THEN
          ALTER TABLE products ADD COLUMN display_currency VARCHAR(10);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='is_online') THEN
          ALTER TABLE products ADD COLUMN is_online BOOLEAN DEFAULT FALSE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='went_online_at') THEN
          ALTER TABLE products ADD COLUMN went_online_at TIMESTAMP;
        END IF;
      END IF;

      -- Widen money columns so high unit price × quantity cannot overflow at checkout.
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'orders') THEN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'orders' AND column_name = 'total'
            AND numeric_precision = 12 AND numeric_scale = 2
        ) THEN
          ALTER TABLE orders ALTER COLUMN subtotal TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN discount TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN tax TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN total TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN display_subtotal TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN display_discount TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN display_tax TYPE DECIMAL(18,2);
          ALTER TABLE orders ALTER COLUMN display_total TYPE DECIMAL(18,2);
        END IF;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'order_items') THEN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'order_items' AND column_name = 'total_price'
            AND numeric_precision = 12 AND numeric_scale = 2
        ) THEN
          ALTER TABLE order_items ALTER COLUMN unit_price TYPE DECIMAL(18,2);
          ALTER TABLE order_items ALTER COLUMN total_price TYPE DECIMAL(18,2);
          ALTER TABLE order_items ALTER COLUMN display_price TYPE DECIMAL(18,2);
        END IF;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'products' AND column_name = 'price'
            AND numeric_precision = 12 AND numeric_scale = 2
        ) THEN
          ALTER TABLE products ALTER COLUMN price TYPE DECIMAL(18,2);
          ALTER TABLE products ALTER COLUMN display_price TYPE DECIMAL(18,2);
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
      price DECIMAL(18,2) NOT NULL DEFAULT 0,
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
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='customer_user_id') THEN
        ALTER TABLE orders ADD COLUMN customer_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL;
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
      subtotal DECIMAL(18,2) NOT NULL DEFAULT 0,
      discount DECIMAL(18,2) NOT NULL DEFAULT 0,
      tax DECIMAL(18,2) NOT NULL DEFAULT 0,
      total DECIMAL(18,2) NOT NULL DEFAULT 0,
      display_subtotal DECIMAL(18,2),
      display_discount DECIMAL(18,2),
      display_tax DECIMAL(18,2),
      display_total DECIMAL(18,2),
      display_currency VARCHAR(10),
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
      unit_price DECIMAL(18,2) NOT NULL,
      total_price DECIMAL(18,2) NOT NULL,
      barcode VARCHAR(50),
      currency VARCHAR(10),
      display_price DECIMAL(18,2),
      display_currency VARCHAR(10)
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
  // Token-revocation watermark. Stamped to NOW() on password change and
  // password reset. authenticateToken rejects any JWT whose `iat` is
  // older than this timestamp, so the user's primary defensive action
  // (change/reset password) immediately revokes every existing session
  // including ones held by an attacker who stole a token. Existing rows
  // get NULL so legacy sessions still validate — the column only gates
  // tokens issued before a password change that has actually happened.
  await pool.query(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='password_changed_at') THEN
          ALTER TABLE users ADD COLUMN password_changed_at TIMESTAMP;
        END IF;
      END IF;
    END $$;
  `);

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
    // ==================== FAVORITE STORES ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS favorite_stores (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, store_id)
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorite_stores_user ON favorite_stores(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorite_stores_store ON favorite_stores(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorites_user ON favorites(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_favorites_product ON favorites(product_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_user ON store_staff(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_store ON store_staff(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_staff_status ON store_staff(status);`);

  // ==================== PRODUCT IMAGE HASHES (anti-bot: duplicate detection) ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_image_hashes (
      id SERIAL PRIMARY KEY,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      image_hash VARCHAR(64) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(store_id, image_hash)
    );
  `);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_image_hashes_store ON product_image_hashes(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_image_hashes_hash ON product_image_hashes(store_id, image_hash);`);

  // ==================== STORES: first_product_approved column ====================
  await pool.query(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stores') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='first_product_approved') THEN
          ALTER TABLE stores ADD COLUMN first_product_approved BOOLEAN DEFAULT FALSE;
        END IF;
      END IF;
    END $$;
  `);

  // ==================== PRODUCTS: pending_approval column ====================
  await pool.query(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='pending_approval') THEN
          ALTER TABLE products ADD COLUMN pending_approval BOOLEAN DEFAULT FALSE;
        END IF;
      END IF;
    END $$;
  `);

  // Mark existing stores with online products as approved
  await pool.query(`
    UPDATE stores SET first_product_approved = TRUE
    WHERE first_product_approved IS NOT TRUE
    AND id IN (SELECT DISTINCT store_id FROM products WHERE is_online = TRUE);
  `);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_is_online ON products(store_id, is_online);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_store_created ON products(store_id, created_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_pending_approval ON products(pending_approval) WHERE pending_approval = TRUE;`);

  // ==================== MARKETPLACE HOT-PATH INDEXES ====================
  // Every public marketplace listing query filters on
  //   WHERE is_online = TRUE AND quantity > 0
  // and sorts by either created_at DESC (new arrivals) or view_count DESC
  // (trending). Without dedicated indexes the planner falls back to a
  // sequential scan of `products` once the catalog grows past a few
  // thousand rows, which is the single biggest read-path bottleneck this
  // app will hit at scale.
  //
  // Partial indexes (`WHERE is_online = TRUE AND quantity > 0`) only
  // index the rows that match the filter, so they stay small even as the
  // overall product table grows (offline / out-of-stock products are
  // excluded from the index). They also self-maintain — a product going
  // offline is simply removed from the index by Postgres.
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_products_marketplace_recent
    ON products (created_at DESC)
    WHERE is_online = TRUE AND quantity > 0;
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_products_marketplace_trending
    ON products (view_count DESC NULLS LAST, created_at DESC)
    WHERE is_online = TRUE AND quantity > 0;
  `);

  // ==================== STORE VISITS (analytics) ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS store_visits (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      user_id VARCHAR(100),
      visited_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_visits_store_date ON store_visits(store_id, visited_at);`);

  // ==================== EXPENSES ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS expenses (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      category VARCHAR(100) NOT NULL DEFAULT 'General',
      amount DECIMAL(12,2) NOT NULL DEFAULT 0,
      description TEXT,
      expense_date DATE DEFAULT CURRENT_DATE,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_expenses_store_date ON expenses(store_id, expense_date);`);

  // ==================== CUSTOMER CREDITS ====================
  await pool.query(`
    CREATE TABLE IF NOT EXISTS customer_credits (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      customer_name VARCHAR(100) NOT NULL,
      customer_phone VARCHAR(50),
      amount DECIMAL(12,2) NOT NULL DEFAULT 0,
      notes TEXT,
      status VARCHAR(20) DEFAULT 'outstanding',
      created_at TIMESTAMP DEFAULT NOW(),
      settled_at TIMESTAMP
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_customer_credits_store ON customer_credits(store_id, status);`);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_verification_codes_email_created ON verification_codes(email, created_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_views_user ON product_views(user_id, viewed_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_views_product_date ON product_views(product_id, viewed_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_search_queries_user ON search_queries(user_id, searched_at);`);
  
  await patchForeignKeyConstraints();
  console.log('✅ Auth & auxiliary tables initialized');
}

// ==================== SUBSCRIPTION TABLES ====================
async function initSubscriptionTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS subscription_tiers (
      id SERIAL PRIMARY KEY,
      name VARCHAR(50) NOT NULL,
      slug VARCHAR(30) NOT NULL UNIQUE,
      online_slots INTEGER NOT NULL,
      price_usd_monthly DECIMAL(10,2) DEFAULT 0,
      sort_order INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS store_subscriptions (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      tier_id INTEGER NOT NULL REFERENCES subscription_tiers(id),
      status VARCHAR(20) DEFAULT 'pending',
      starts_at TIMESTAMP,
      expires_at TIMESTAMP,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS subscription_payments (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      tier_id INTEGER NOT NULL REFERENCES subscription_tiers(id),
      payment_track VARCHAR(20) NOT NULL,
      reference_code VARCHAR(50) UNIQUE,
      amount_usd DECIMAL(10,2),
      status VARCHAR(20) DEFAULT 'pending',
      stripe_session_id VARCHAR(255),
      verified_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
      verified_at TIMESTAMP,
      notes TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  const tiers = [
    { name: 'Free', slug: 'free', online_slots: 5, price_usd_monthly: 0, sort_order: 0 },
    { name: 'Starter', slug: 'starter', online_slots: 25, price_usd_monthly: 4.99, sort_order: 1 },
    { name: 'Business', slug: 'business', online_slots: 100, price_usd_monthly: 14.99, sort_order: 2 },
    { name: 'Pro', slug: 'pro', online_slots: 500, price_usd_monthly: 39.99, sort_order: 3 },
    { name: 'Enterprise', slug: 'enterprise', online_slots: 2000, price_usd_monthly: 99.99, sort_order: 4 },
  ];

  for (const tier of tiers) {
    await pool.query(
      `INSERT INTO subscription_tiers (name, slug, online_slots, price_usd_monthly, sort_order)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (slug) DO UPDATE SET
         name = EXCLUDED.name,
         online_slots = EXCLUDED.online_slots,
         price_usd_monthly = EXCLUDED.price_usd_monthly,
         sort_order = EXCLUDED.sort_order`,
      [tier.name, tier.slug, tier.online_slots, tier.price_usd_monthly, tier.sort_order]
    );
  }

  // One-time seed: stores with products but none online get first 5 marked online
  await pool.query(`
    WITH stores_needing_seed AS (
      SELECT store_id FROM products GROUP BY store_id
      HAVING SUM(CASE WHEN is_online THEN 1 ELSE 0 END) = 0
    ),
    ranked AS (
      SELECT p.id, ROW_NUMBER() OVER (PARTITION BY p.store_id ORDER BY p.created_at ASC) as rn
      FROM products p
      JOIN stores_needing_seed s ON p.store_id = s.store_id
    )
    UPDATE products p SET is_online = TRUE, went_online_at = COALESCE(p.went_online_at, p.created_at)
    FROM ranked r
    WHERE p.id = r.id AND r.rn <= 5;
  `);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_subscriptions_store ON store_subscriptions(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_subscriptions_status ON store_subscriptions(status, expires_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_subscription_payments_store ON subscription_payments(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_subscription_payments_status ON subscription_payments(status);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_subscription_payments_ref ON subscription_payments(reference_code);`);

  console.log('✅ Subscription tables initialized');
}

async function initChatTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_conversations (
      id SERIAL PRIMARY KEY,
      customer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      last_message_at TIMESTAMP DEFAULT NOW(),
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(customer_id, store_id)
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id SERIAL PRIMARY KEY,
      conversation_id INTEGER NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
      sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      read_at TIMESTAMP
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_conversations_customer ON chat_conversations(customer_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_conversations_store ON chat_conversations(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation ON chat_messages(conversation_id, created_at);`);
  console.log('✅ Chat tables initialized');
}

async function initSupportTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS support_tickets (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      subject VARCHAR(200) NOT NULL,
      category VARCHAR(50) DEFAULT 'general',
      status VARCHAR(20) DEFAULT 'open',
      priority VARCHAR(20) DEFAULT 'normal',
      assigned_admin_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      last_message_at TIMESTAMP DEFAULT NOW(),
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS support_ticket_messages (
      id SERIAL PRIMARY KEY,
      ticket_id INTEGER NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
      sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      sender_role VARCHAR(20) NOT NULL DEFAULT 'user',
      body TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      read_at TIMESTAMP
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_support_tickets_user ON support_tickets(user_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status, last_message_at DESC);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_support_messages_ticket ON support_ticket_messages(ticket_id, created_at);`);
  await pool.query(`
    ALTER TABLE support_tickets
      ADD COLUMN IF NOT EXISTS image_quota INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS images_sent INTEGER NOT NULL DEFAULT 0;
  `);
  await pool.query(`
    ALTER TABLE support_ticket_messages
      ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) NOT NULL DEFAULT 'text',
      ADD COLUMN IF NOT EXISTS attachment_url VARCHAR(500),
      ADD COLUMN IF NOT EXISTS request_status VARCHAR(20);
  `);
  console.log('✅ Support ticket tables initialized');
}

async function initSponsoredProductTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sponsorship_pricing (
      id SERIAL PRIMARY KEY,
      scope_type VARCHAR(20) NOT NULL UNIQUE,
      label VARCHAR(80) NOT NULL,
      price_usd_per_day DECIMAL(10,2) NOT NULL,
      radius_unit_km INTEGER DEFAULT 5,
      sort_order INTEGER DEFAULT 0,
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS sponsored_product_payments (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      scope_type VARCHAR(20) NOT NULL,
      radius_km INTEGER,
      duration_days INTEGER NOT NULL,
      target_village VARCHAR(100),
      target_city VARCHAR(100),
      target_country VARCHAR(100),
      target_country_code VARCHAR(2),
      target_city_id VARCHAR(100),
      center_lat DECIMAL(10,7),
      center_lng DECIMAL(10,7),
      amount_usd DECIMAL(10,2) NOT NULL,
      payment_track VARCHAR(20) NOT NULL DEFAULT 'syria_agent',
      reference_code VARCHAR(50) UNIQUE,
      status VARCHAR(20) DEFAULT 'pending',
      verified_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
      verified_at TIMESTAMP,
      notes TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS sponsored_product_campaigns (
      id SERIAL PRIMARY KEY,
      payment_id INTEGER REFERENCES sponsored_product_payments(id) ON DELETE SET NULL,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      scope_type VARCHAR(20) NOT NULL,
      radius_km INTEGER,
      duration_days INTEGER NOT NULL,
      target_village VARCHAR(100),
      target_city VARCHAR(100),
      target_country VARCHAR(100),
      target_country_code VARCHAR(2),
      target_city_id VARCHAR(100),
      center_lat DECIMAL(10,7),
      center_lng DECIMAL(10,7),
      amount_usd DECIMAL(10,2) NOT NULL,
      status VARCHAR(20) DEFAULT 'active',
      starts_at TIMESTAMP DEFAULT NOW(),
      expires_at TIMESTAMP NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  const pricing = [
    { scope: 'radius', label: 'Nearby radius', price: 0.50, unit: 5, order: 0 },
    { scope: 'village', label: 'Village', price: 0.80, unit: 5, order: 1 },
    { scope: 'city', label: 'City', price: 2.00, unit: 5, order: 2 },
    { scope: 'country', label: 'Country', price: 5.00, unit: 5, order: 3 },
    { scope: 'world', label: 'Worldwide', price: 10.00, unit: 5, order: 4 },
  ];

  for (const p of pricing) {
    // IMPORTANT: seed only — never overwrite admin-edited prices on restart.
    // Previously this used DO UPDATE which silently reverted any pricing the
    // admin changed in the dashboard back to the hard-coded defaults on the
    // next backend boot. We still refresh sort_order so a future migration
    // can re-order scopes without losing the saved price.
    await pool.query(
      `INSERT INTO sponsorship_pricing (scope_type, label, price_usd_per_day, radius_unit_km, sort_order)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (scope_type) DO UPDATE SET
         sort_order = EXCLUDED.sort_order`,
      [p.scope, p.label, p.price, p.unit, p.order]
    );
  }

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_sponsor_payments_store ON sponsored_product_payments(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_sponsor_payments_status ON sponsored_product_payments(status);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_sponsor_campaigns_store ON sponsored_product_campaigns(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_sponsor_campaigns_active ON sponsored_product_campaigns(status, expires_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_sponsor_campaigns_product ON sponsored_product_campaigns(product_id);`);

  console.log('✅ Sponsored product tables initialized');
}

// Promo tables are also created by the admin-dashboard on startup, but the
// backend reads/writes them directly in routes/subscriptions.js and
// services/subscription.js (promo redemption + auto-expiry). Initializing
// them here means the backend can boot cleanly even if the admin-dashboard
// has not been deployed yet — previously, /api/subscription/promo/redeem
// crashed with "relation does not exist" on a fresh database.
//
// Schema matches admin-dashboard/server.js exactly so both initializers
// converge on the same shape regardless of which one runs first.
async function initPromoTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS promo_codes (
      id SERIAL PRIMARY KEY,
      code VARCHAR(50) NOT NULL UNIQUE,
      type VARCHAR(20) DEFAULT 'discount',
      discount_percent INTEGER DEFAULT 0,
      discount_fixed DECIMAL(10,2) DEFAULT 0,
      tier_slug VARCHAR(30),
      grant_days INTEGER DEFAULT 0,
      max_redemptions INTEGER,
      times_used INTEGER DEFAULT 0,
      expires_at TIMESTAMP,
      is_active BOOLEAN DEFAULT TRUE,
      min_account_age_days INTEGER,
      max_account_age_days INTEGER,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  // Catch up legacy installs where the table exists from an older
  // admin-dashboard but is missing the newer columns.
  await pool.query(`
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'promo_codes') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='type') THEN
          ALTER TABLE promo_codes ADD COLUMN type VARCHAR(20) DEFAULT 'discount';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='tier_slug') THEN
          ALTER TABLE promo_codes ADD COLUMN tier_slug VARCHAR(30);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='grant_days') THEN
          ALTER TABLE promo_codes ADD COLUMN grant_days INTEGER DEFAULT 0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='min_account_age_days') THEN
          ALTER TABLE promo_codes ADD COLUMN min_account_age_days INTEGER;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='max_account_age_days') THEN
          ALTER TABLE promo_codes ADD COLUMN max_account_age_days INTEGER;
        END IF;
      END IF;
    END $$;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS promo_redemptions (
      id SERIAL PRIMARY KEY,
      promo_id INTEGER NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      tier_id INTEGER REFERENCES subscription_tiers(id) ON DELETE SET NULL,
      starts_at TIMESTAMP DEFAULT NOW(),
      expires_at TIMESTAMP,
      status VARCHAR(20) DEFAULT 'active',
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(promo_id, store_id)
    );
  `);

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_promo_redemptions_store ON promo_redemptions(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_promo_redemptions_status ON promo_redemptions(status, expires_at);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_promo_codes_active ON promo_codes(is_active, expires_at);`);

  console.log('✅ Promo tables initialized');
}

async function initReviewTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS store_reviews (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
      comment TEXT,
      status VARCHAR(20) DEFAULT 'active',
      removed_at TIMESTAMP,
      removed_by_admin_id INTEGER,
      removal_reason TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(store_id, user_id)
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_reviews_store ON store_reviews(store_id, status, created_at DESC);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_store_reviews_user ON store_reviews(user_id);`);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_reviews (
      id SERIAL PRIMARY KEY,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
      comment TEXT,
      status VARCHAR(20) DEFAULT 'active',
      removed_at TIMESTAMP,
      removed_by_admin_id INTEGER,
      removal_reason TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(product_id, user_id)
    );
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_reviews_product ON product_reviews(product_id, status, created_at DESC);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_product_reviews_user ON product_reviews(user_id);`);

  await pool.query(`
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='rating') THEN
          ALTER TABLE products ADD COLUMN rating DECIMAL(2,1) DEFAULT 5.0;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='review_count') THEN
          ALTER TABLE products ADD COLUMN review_count INTEGER DEFAULT 0;
        END IF;
      END IF;
    END $$;
  `);

  console.log('✅ Review tables initialized');
}

async function initReportTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS content_reports (
      id SERIAL PRIMARY KEY,
      target_type VARCHAR(20) NOT NULL,
      target_id INTEGER NOT NULL,
      store_id INTEGER,
      reporter_id INTEGER NOT NULL,
      reporter_role VARCHAR(20) NOT NULL DEFAULT 'user',
      reason TEXT NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'open',
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMP DEFAULT NOW(),
      resolved_at TIMESTAMP,
      resolved_by INTEGER,
      resolution_note TEXT
    );
  `);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS idx_content_reports_status ON content_reports(status, created_at DESC);`
  );
  await pool.query(
    `CREATE INDEX IF NOT EXISTS idx_content_reports_target ON content_reports(target_type, target_id);`
  );
  console.log('✅ Report tables initialized');
}

module.exports = {
  initInventoryTables,
  initAuthTables,
  initSubscriptionTables,
  initChatTables,
  initSupportTables,
  initSponsoredProductTables,
  initPromoTables,
  initReviewTables,
  initReportTables,
};