// middleware/validation.js
const { z } = require('zod');

// ==================== ZOD HELPERS ====================
function numField(opts = {}) {
  return z.preprocess((v) => {
    if (v === '' || v === null || v === undefined) return undefined;
    const n = Number(v);
    return isNaN(n) ? v : n;
  }, opts.optional ? z.number().nullish() : z.number());
}

// ==================== ZOD SCHEMAS ====================
const schemas = {
  register: z.object({
    full_name: z.string().min(1).max(100),
    email: z.string().email().max(255),
    phone: z.string().max(50).nullish().transform(v => v || undefined),
    password: z.string().min(1),
    role: z.enum(['store_owner', 'customer']).nullish().transform(v => v || undefined),
    store: z.object({
      name: z.string().min(1).max(100),
      city: z.string().min(1).max(100),
      location_description: z.string().max(200).nullish().transform(v => v || undefined),
      country: z.string().max(100).nullish().transform(v => v || undefined),
      lat: numField({ optional: true }),
      lng: numField({ optional: true }),
      phone: z.string().max(50).nullish().transform(v => v || undefined),
      city_id: z.string().max(100).nullish().transform(v => v || undefined),
      country_code: z.preprocess(v => typeof v === 'string' ? v.toLowerCase().substring(0, 2) : v, z.string().max(2).nullish()),
      village: z.string().max(100).nullish().transform(v => v || undefined),
    }).nullish().transform(v => v || undefined),
    preferred_language: z.string().max(10).nullish().transform(v => v || undefined),
  }),
  verifyEmail: z.object({
    email: z.string().email(),
    code: z.string().min(1),
  }),
  resendVerification: z.object({
    email: z.string().email(),
  }),
  login: z.object({
    email: z.string().email(),
    password: z.string().min(1),
  }),
  forgotPassword: z.object({
    email: z.string().email(),
  }),
  resetPassword: z.object({
    email: z.string().email(),
    code: z.string().min(1),
    new_password: z.string().min(1),
  }),
  updateProfile: z.object({
    full_name: z.string().max(100).optional(),
    phone: z.string().max(50).optional(),
  }),
  changePassword: z.object({
    current_password: z.string().min(1),
    new_password: z.string().min(1),
  }),
  updateLanguage: z.object({
    preferred_language: z.string().max(10),
  }),
  checkout: z.object({
    items: z.array(z.object({
      product_id: numField().refine(n => Number.isInteger(n) && n > 0, { message: 'product_id must be a positive integer' }),
      quantity: numField().refine(n => Number.isInteger(n) && n > 0, { message: 'quantity must be a positive integer' }),
    })).min(1),
    payment_method: z.string().max(50).optional(),
    notes: z.string().max(500).optional(),
  }),
  createOrder: z.object({
    receipt_number: z.string().max(50).optional(),
    items: z.array(z.object({
      product_id: numField({ optional: true }).refine(n => n === undefined || n === null || Number.isInteger(n), { message: 'product_id must be an integer' }),
      quantity: numField().refine(n => Number.isInteger(n) && n > 0, { message: 'quantity must be a positive integer' }),
      unit_price: numField({ optional: true }).refine(n => n === undefined || n === null || n >= 0, { message: 'unit_price must be non-negative' }),
      total_price: numField({ optional: true }).refine(n => n === undefined || n === null || n >= 0, { message: 'total_price must be non-negative' }),
      product_name: z.string().max(200).optional(),
      barcode: z.string().max(50).nullish().transform(v => v ?? undefined),
      currency: z.string().max(10).optional(),
    })).min(1),
    customer_name: z.string().max(100).optional(),
    customer_phone: z.string().max(50).optional(),
    discount: numField({ optional: true }).refine(n => n === undefined || n === null || n >= 0, { message: 'discount must be non-negative' }),
    tax: numField({ optional: true }).refine(n => n === undefined || n === null || n >= 0, { message: 'tax must be non-negative' }),
    payment_method: z.string().max(50).optional(),
    notes: z.string().max(500).optional(),
  }),
  updateStore: z.object({
    name: z.string().max(100).optional(),
    city: z.string().max(100).optional(),
    location_description: z.string().max(200).optional(),
    country: z.string().max(100).optional(),
    phone: z.string().max(50).optional(),
    lat: numField({ optional: true }),
    lng: numField({ optional: true }),
    city_id: z.string().max(100).optional(),
    country_code: z.preprocess(v => typeof v === 'string' ? v.toLowerCase().substring(0, 2) : v, z.string().max(2).optional()),
  }),
  createProduct: z.object({
    name: z.string().min(1).max(200),
    price: numField().refine(n => n >= 0, { message: 'price must be non-negative' }),
    quantity: numField().refine(n => Number.isInteger(n) && n >= 0, { message: 'quantity must be a non-negative integer' }),
    description: z.string().max(1000).optional(),
    barcode: z.string().max(50).optional(),
    category_id: numField({ optional: true }).refine(n => n === undefined || n === null || (Number.isInteger(n) && n > 0), { message: 'category_id must be a positive integer' }),
    low_stock_threshold: numField({ optional: true }).refine(n => n === undefined || n === null || (Number.isInteger(n) && n >= 0), { message: 'low_stock_threshold must be a non-negative integer' }),
    currency: z.string().max(10).optional(),
  }),
  updateProduct: z.object({
    name: z.string().max(200).optional(),
    price: numField({ optional: true }).refine(n => n === undefined || n === null || n >= 0, { message: 'price must be non-negative' }),
    quantity: numField({ optional: true }).refine(n => n === undefined || n === null || (Number.isInteger(n) && n >= 0), { message: 'quantity must be a non-negative integer' }),
    description: z.string().max(1000).optional(),
    barcode: z.string().max(50).optional(),
    category_id: numField({ optional: true }).refine(n => n === undefined || n === null || (Number.isInteger(n) && n > 0), { message: 'category_id must be a positive integer' }),
    low_stock_threshold: numField({ optional: true }).refine(n => n === undefined || n === null || (Number.isInteger(n) && n >= 0), { message: 'low_stock_threshold must be a non-negative integer' }),
    existing_images: z.string().optional(),
    currency: z.string().max(10).optional(),
  }),
  sponsorStore: z.object({
    tier: z.number().optional(),
    expiresAt: z.string().optional(),
  }),
  receiptSettings: z.object({
    footer_message: z.string().max(255).optional(),
    show_logo: z.boolean().optional(),
    show_barcode: z.boolean().optional(),
    currency_symbol: z.string().max(10).optional(),
  }),
  geocodeSearch: z.object({
    q: z.string().min(1).max(200),
    lang: z.string().max(10).optional(),
  }),
  geocodeReverse: z.object({
    lat: numField(),
    lng: numField(),
    lang: z.string().max(10).optional(),
  }),
  nearby: z.object({
    lat: numField().refine(n => n >= -90 && n <= 90, { message: 'lat must be between -90 and 90' }),
    lng: numField().refine(n => n >= -180 && n <= 180, { message: 'lng must be between -180 and 180' }),
    radius: numField({ optional: true }).refine(n => n === undefined || n === null || (n >= 0.1 && n <= 100), { message: 'radius must be between 0.1 and 100 km' }),
  }),
  search: z.object({
    q: z.string().min(1).max(100),
    limit: numField({ optional: true }),
  }),
  productSearch: z.object({
    q: z.string().min(1).max(100),
    limit: numField({ optional: true }),
  }),
  trackSearch: z.object({
    query: z.string().min(2).max(200),
  }),
  barcodeValidate: z.object({
    code: z.string().min(1).max(50),
  }),
  migrateLocations: z.object({}),

  // ==================== NEW: STAFF / INVITATION ====================
  inviteStaff: z.object({
    email: z.string().email(),
    can_manage_inventory: z.boolean().optional(),
  }),
  respondInvitation: z.object({
    action: z.enum(['accept', 'reject']),
  }),
  updateStaffPermissions: z.object({
    can_manage_inventory: z.boolean(),
  }),
};

function validate(schema) {
  return (req, res, next) => {
    try {
      const result = schema.parse(req.body);
      req.validatedBody = result;
      next();
    } catch (err) {
      console.error('Validation error:', err);

      if (err && (err instanceof z.ZodError || err.constructor?.name === 'ZodError' || err.name === 'ZodError')) {
        const issues = err.issues || err.errors || [];
        return res.status(400).json({
          error: 'Validation failed',
          details: issues.map(e => ({
            field: (e.path || []).join('.'),
            message: e.message
          })),
        });
      }
      next(err);
    }
  };
}

function validateQuery(schema) {
  return (req, res, next) => {
    try {
      const result = schema.parse(req.query);
      req.validatedQuery = result;
      next();
    } catch (err) {
      console.error('Query validation error:', err);

      if (err && (err instanceof z.ZodError || err.constructor?.name === 'ZodError' || err.name === 'ZodError')) {
        const issues = err.issues || err.errors || [];
        return res.status(400).json({
          error: 'Validation failed',
          details: issues.map(e => ({
            field: (e.path || []).join('.'),
            message: e.message
          })),
        });
      }
      next(err);
    }
  };
}

module.exports = { schemas, validate, validateQuery };