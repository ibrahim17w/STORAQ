//routes/index.js
const authRoutes = require('./auth');
const userRoutes = require('./user');
const storeRoutes = require('./stores');
const productRoutes = require('./products');
const barcodeRoutes = require('./barcode');
const orderRoutes = require('./orders');
const marketplaceRoutes = require('./marketplace');
const geocodeRoutes = require('./geocode');
const searchRoutes = require('./search');
const categoryRoutes = require('./categories');
const healthRoutes = require('./health');
const subscriptionRoutes = require('./subscriptions');
const analyticsRoutes = require('./analytics');
const chatRoutes = require('./chat');
const supportRoutes = require('./support');
const sponsoredProductRoutes = require('./sponsored_products');
const platformRatesRoutes = require('./platform_rates');
const { authLimiter } = require('../middleware/auth');

function mountRoutes(app) {
  app.use('/api/auth', authLimiter, authRoutes);
  app.use('/api', userRoutes);
  app.use('/api', healthRoutes);
  app.use('/api', geocodeRoutes);
  app.use('/api', searchRoutes);
  app.use('/api', categoryRoutes);
  app.use('/api', barcodeRoutes);
  app.use('/api', productRoutes);
  app.use('/api', storeRoutes);
  app.use('/api', orderRoutes);
  app.use('/api', subscriptionRoutes);
  app.use('/api', analyticsRoutes);
  app.use('/api', chatRoutes);
  app.use('/api', supportRoutes);
  app.use('/api', sponsoredProductRoutes);
  app.use('/api', platformRatesRoutes);
  // marketplaceRoutes MUST come LAST because it likely has catch-all or broad matchers
  app.use('/api', marketplaceRoutes);
}

module.exports = { mountRoutes };