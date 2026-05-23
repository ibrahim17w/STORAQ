require('dotenv').config();
const { Pool } = require('pg');
const { faker } = require('@faker-js/faker');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const CATEGORIES = [
  'Electronics', 'Clothing', 'Food', 'Home', 'Sports',
  'Books', 'Toys', 'Beauty', 'Automotive', 'Garden'
];

// Syria-focused with global mix
const COUNTRIES = [
  // Syria (60% weight - appears multiple times for higher probability)
  'Syria', 'Syria', 'Syria', 'Syria', 'Syria', 'Syria',
  // Middle East neighbors
  'Lebanon', 'Jordan', 'Iraq', 'Turkey', 'UAE', 'Saudi Arabia', 'Egypt',
  // Global
  'USA', 'UK', 'Canada', 'Germany', 'France', 'Japan', 'India', 'Brazil', 'Australia'
];

// Syrian cities for realistic local data
const SYRIAN_CITIES = [
  'Damascus', 'Aleppo', 'Homs', 'Latakia', 'Hama', 'Raqqa', 'Deir ez-Zor',
  'Tartus', 'Idlib', 'Daraa', 'Al-Hasakah', 'Qamishli', 'Swedaa', 'Douma',
  'Harasta', 'Jobar', 'Barzeh', 'Malki', 'Mazzeh', 'Salhieh'
];

// Syrian store names (authentic local flavor)
const SYRIAN_STORE_NAMES = [
  'Souq Al-Hamidiyah', 'Al-Basha Electronics', 'Damascus Gold',
  'Aleppo Textiles', 'Latakia Fresh', 'Homs Furniture', 'Tartus Marine',
  'Bakdash Ice Cream', 'Al-Nour Books', 'Shahba Mall', 'Omayyad Crafts',
  'Barada Foods', 'Syrian Sweet House', 'Al-Fayhaa Market', 'Old City Bazaar'
];

// Syrian product names (local flavor)
const SYRIAN_PRODUCTS = [
  'Aleppo Soap', 'Damascus Rose Oil', 'Syrian Dates', 'Baklava Mix',
  'Handmade Mosaic', 'Brass Coffee Pot', 'Olive Oil (Latakia)', 'Pistachios (Aleppo)',
  'Syrian Cotton Scarf', 'Traditional Thobe', 'Damascus Steel Knife',
  'Arak Glass Set', 'Hookah (Shisha)', 'Maamoul Cookies', 'Sujuk Sausage',
  'Fattoush Spices', 'Tamarind Drink', 'Rose Water Spray', 'Copper Tray',
  'Handwoven Carpet'
];

// Global product names for non-Syrian stores
const GLOBAL_PRODUCTS = [
  'Wireless Earbuds', 'Smart Watch', 'Running Shoes', 'Yoga Mat',
  'Coffee Maker', 'Bluetooth Speaker', 'Laptop Stand', 'LED Desk Lamp',
  'Backpack', 'Water Bottle', 'Sunglasses', 'Winter Jacket',
  'Kitchen Knife Set', 'Plant Pot', 'Board Game', 'Skincare Set'
];

function truncate(str, maxLen) {
  if (!str) return str;
  return str.length > maxLen ? str.substring(0, maxLen) : str;
}

// Weighted random picker
function weightedPick(items, weights) {
  const total = weights.reduce((a, b) => a + b, 0);
  let random = Math.random() * total;
  for (let i = 0; i < items.length; i++) {
    random -= weights[i];
    if (random <= 0) return items[i];
  }
  return items[items.length - 1];
}

function isSyria(country) {
  return country === 'Syria';
}

async function seed() {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    console.log('🌱 Seeding demo data with Syria focus...');
    
    // ========== 1. CREATE DEMO USERS (80 sellers + 120 buyers = 200 total) ==========
    const users = [];
    const syrianNames = [
      ['Omar', 'Al-Hassan'], ['Fatima', 'Al-Khatib'], ['Ahmad', 'Al-Masri'],
      ['Layla', 'Haddad'], ['Khaled', 'Ibrahim'], ['Nour', 'Suleiman'],
      ['Mohammad', 'Abbas'], ['Hana', 'Fakhoury'], ['Youssef', 'Khoury'],
      ['Rana', 'Makhlouf'], ['Bassel', 'Shalish'], ['Amal', 'Zahra'],
      ['Tariq', 'Joud'], ['Samira', 'Bakri'], ['Fadi', 'Nasr'],
      ['Dima', 'Kuzbari'], ['Wael', 'Nader'], ['Maya', 'Hafez'],
      ['Rami', 'Tlass'], ['Samar', 'Deeb']
    ];
    
    for (let i = 0; i < 200; i++) {
      const isSeller = i < 80;
      const isSyrian = Math.random() < 0.65; // 65% Syrian users
      
      let firstName, lastName, email, phone;
      
      if (isSyrian && i < syrianNames.length) {
        [firstName, lastName] = syrianNames[i % syrianNames.length];
        email = truncate(`${firstName.toLowerCase()}.${lastName.toLowerCase()}${faker.number.int(999)}@email.com`, 100);
        phone = truncate('+963' + faker.string.numeric(9), 50); // Syrian country code
      } else {
        firstName = faker.person.firstName();
        lastName = faker.person.lastName();
        email = truncate(faker.internet.email({ firstName, lastName }).toLowerCase(), 100);
        phone = truncate(faker.phone.number().replace(/\D/g, '').substring(0, 15), 50);
      }
      
      const result = await client.query(`
        INSERT INTO users (full_name, email, phone, password_hash, role, preferred_language, email_verified, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, true, NOW())
        ON CONFLICT (email) DO NOTHING
        RETURNING id
      `, [
        truncate(`${firstName} ${lastName}`, 100),
        email,
        phone,
        '$2b$10$demo_hash_not_real',
        isSeller ? 'store_owner' : 'customer',
        isSyrian ? 'ar' : truncate(['en', 'fr', 'es', 'de', 'tr'][Math.floor(Math.random() * 5)], 10)
      ]);
      
      if (result.rows[0]) users.push(result.rows[0].id);
    }
    console.log(`✅ Created ${users.length} users (${Math.round(users.length * 0.65)} Syrian)`);
    
    // ========== 2. CREATE DEMO STORES (60 stores: 40 Syria + 20 global) ==========
    const stores = [];
    const sellerIds = users.slice(0, 80);
    
    for (let i = 0; i < 60; i++) {
      const isSyrianStore = i < 40; // 40 Syrian, 20 global
      const country = isSyrianStore ? 'Syria' : faker.helpers.arrayElement(
        COUNTRIES.filter(c => c !== 'Syria')
      );
      const isSponsored = i < 8; // First 8 stores are sponsored
      
      let storeName, city, village;
      
      if (isSyrianStore) {
        storeName = truncate(faker.helpers.arrayElement(SYRIAN_STORE_NAMES), 100);
        city = faker.helpers.arrayElement(SYRIAN_CITIES);
        village = truncate(faker.helpers.arrayElement([
          'Old City', 'Al-Muhajreen', 'Salhieh', 'Mazan', 'Baramkeh',
          'Masaken Barzeh', 'Al-Qusour', 'Al-Adawi', 'Rukn al-Din', 'Al-Malki'
        ]), 100);
      } else {
        storeName = truncate(faker.company.name(), 100);
        city = truncate(faker.location.city(), 100);
        village = truncate(faker.location.streetAddress(), 100);
      }
      
      // Syria coordinates (rough bounding box)
      const lat = isSyrianStore 
        ? parseFloat((33.0 + Math.random() * 4.5).toFixed(6)) // 33.0 to 37.5
        : parseFloat(faker.location.latitude({ min: -35, max: 60 }).toFixed(6));
      const lng = isSyrianStore
        ? parseFloat((35.5 + Math.random() * 5.5).toFixed(6)) // 35.5 to 41.0
        : parseFloat(faker.location.longitude({ min: -120, max: 140 }).toFixed(6));
      
      const result = await client.query(`
        INSERT INTO stores (owner_id, name, city, village, country, phone, lat, lng, image_url, is_sponsored, sponsorship_tier, sponsorship_expires_at, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
        RETURNING id
      `, [
        sellerIds[i % sellerIds.length],
        storeName,
        city,
        village,
        country,
        isSyrianStore ? truncate('+963' + faker.string.numeric(9), 50) : truncate(faker.phone.number().replace(/\D/g, '').substring(0, 15), 50),
        lat,
        lng,
        truncate(`https://picsum.photos/seed/${faker.string.alphanumeric(8)}/400/300`, 255),
        isSponsored,
        isSponsored ? Math.floor(Math.random() * 3) + 1 : 0,
        isSponsored ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) : null
      ]);
      
      stores.push({ id: result.rows[0].id, country });
    }
    console.log(`✅ Created ${stores.length} stores (${stores.filter(s => s.country === 'Syria').length} Syrian)`);
    
    // ========== 3. CREATE DEMO PRODUCTS (1000 products) ==========
    for (let i = 0; i < 1000; i++) {
      const store = stores[i % stores.length];
      const isSyrianProduct = store.country === 'Syria';
      const category = truncate(faker.helpers.arrayElement(CATEGORIES), 50);
      
      let name, description, price;
      
      if (isSyrianProduct && Math.random() < 0.4) {
        // 40% chance of authentic Syrian product in Syrian stores
        name = truncate(faker.helpers.arrayElement(SYRIAN_PRODUCTS), 100);
        description = truncate(`Authentic Syrian ${name.toLowerCase()}. ${faker.commerce.productDescription()}`, 500);
        price = parseFloat(faker.commerce.price({ min: 200, max: 15000, dec: 0 })); // Syrian pounds range
      } else {
        name = truncate(faker.helpers.arrayElement(GLOBAL_PRODUCTS), 100);
        description = truncate(faker.commerce.productDescription(), 500);
        price = parseFloat(faker.commerce.price({ min: 5, max: 5000, dec: 2 }));
      }
      
      await client.query(`
        INSERT INTO products (store_id, name, description, price, quantity, barcode, image_url, category, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
      `, [
        store.id,
        name,
        description,
        price,
        faker.number.int({ min: 1, max: 1000 }),
        truncate(faker.string.numeric(13), 50),
        truncate(`https://picsum.photos/seed/${faker.string.alphanumeric(8)}/400/400`, 255),
        category
      ]);
    }
    console.log('✅ Created 1000 products');
    
    // ========== 4. CREATE DEMO PRODUCT VIEWS (for trending) ==========
    for (let i = 0; i < 500; i++) {
      await client.query(`
        INSERT INTO product_views (product_id, user_id, viewed_at)
        VALUES ($1, $2, NOW() - INTERVAL '${faker.number.int({ min: 1, max: 30 })} days')
      `, [
        faker.number.int({ min: 1, max: 1000 }),
        faker.helpers.arrayElement(users)
      ]);
    }
    console.log('✅ Created 500 product views');
    
    // ========== 5. CREATE DEMO SEARCH QUERIES ==========
    const searchTerms = [
      // Syrian-specific searches
      'aleppo soap', 'damascus rose', 'syrian dates', 'latakia olive oil',
      'baklava', 'mosaic art', 'hookah', 'arabic coffee',
      // Global searches
      'phone', 'shoes', 'laptop', 'food', 'watch', 'dress', 'car', 'book', 'toy', 'chair',
      'headphones', 'backpack', 'sunglasses', 'jacket', 'kitchen'
    ];
    for (let i = 0; i < 300; i++) {
      await client.query(`
        INSERT INTO search_queries (query, user_id, searched_at)
        VALUES ($1, $2, NOW() - INTERVAL '${faker.number.int({ min: 1, max: 30 })} days')
      `, [
        truncate(faker.helpers.arrayElement(searchTerms), 200),
        faker.helpers.arrayElement(users)
      ]);
    }
    console.log('✅ Created 300 search queries');
    
    await client.query('COMMIT');
    console.log('\n🎉 Demo data seeded successfully!');
    console.log('   • 200 users (65% Syrian, ~130 Syrian)');
    console.log('   • 60 stores (40 Syrian + 20 global, 8 sponsored)');
    console.log('   • 1000 products (Syrian stores have authentic local items)');
    console.log('   • 500 product views');
    console.log('   • 300 search queries');
    
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error seeding:', err.message);
    console.error('Detail:', err.detail);
  } finally {
    client.release();
    pool.end();
  }
}

seed();