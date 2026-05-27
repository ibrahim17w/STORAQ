//middleware/auth.js
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => res.status(429).json({ error: 'Too many requests. Please try again later.' }),
});

const loginIpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => res.status(429).json({
    error: 'Too many login attempts from this device. Please try again in 15 minutes.'
  }),
});

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.sendStatus(401);
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.sendStatus(403);
    req.user = user;
    next();
  });
};

const optionalAuth = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) { req.user = null; return next(); }
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) req.user = null;
    else req.user = user;
    next();
  });
};

const requireRealUser = (req, res, next) => {
  authenticateToken(req, res, () => {
    if (req.user.role === 'guest') {
      return res.status(403).json({ error: 'Please log in or create an account to access this feature.' });
    }
    next();
  });
};

module.exports = { authenticateToken, optionalAuth, requireRealUser, authLimiter, loginIpLimiter };
