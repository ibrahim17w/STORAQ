//routes/auth.js
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const router = express.Router();

const { pool } = require('../config/database');
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { authenticateToken, optionalAuth, requireRealUser, authLimiter, loginIpLimiter } = require('../middleware/auth');
const { sanitizeString, getPagination, isValidEmail, serverNow, formatWaitTime, getBaseUrl } = require('../middleware/helpers');
const { validatePasswordStrength, checkLoginLockout, recordFailedLogin, clearLoginAttempts, checkOtpRateLimit, generateOtp, storeOtp, verifyOtp } = require('../middleware/security');
const { transporter, emailReady, sendEmail, emailHtml } = require('../middleware/email');
const { emailTexts, getLang } = require('../config/constants');

// REGISTER
router.post('/register', validate(schemas.register), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { full_name, email, phone, password, role, store, preferred_language } = req.validatedBody;
    const normalizedEmail = email.toLowerCase();
    const lang = getLang(preferred_language || 'en');

    const allowedRoles = ['store_owner', 'customer'];
    const userRole = allowedRoles.includes(role) ? role : 'customer';
    const hashedPassword = await bcrypt.hash(password, 10);

    const userResult = await client.query(
      'INSERT INTO users (full_name, email, phone, password_hash, role, email_verified, preferred_language) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, full_name, email, role',
      [full_name, normalizedEmail, phone || null, hashedPassword, userRole, false, lang]
    );

    if (userRole === 'store_owner' && store) {
      await client.query(
        'INSERT INTO stores (name, city, location_description, country, lat, lng, phone, owner_id, city_id, country_code, village) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
        [
          store.name,
          store.city,
          store.location_description || null,
          store.country || 'Syria',
          store.lat != null ? store.lat : null,
          store.lng != null ? store.lng : null,
          store.phone || null,
          userResult.rows[0].id,
          store.city_id || null,
          store.country_code ? store.country_code.toLowerCase().substring(0, 2) : null,
          store.village || null
        ]
      );
    }
    await client.query('COMMIT');

    const code = generateOtp();
    await storeOtp(normalizedEmail, 'email_verification', code);

    res.status(201).json({ message: 'Created. Check email for verification code.', email: normalizedEmail });

    const texts = emailTexts[lang];
    (async () => {
      try {
        await sendEmail({
          from: process.env.FROM_EMAIL || process.env.SMTP_USER,
          to: normalizedEmail,
          subject: texts.verifySubject,
          html: emailHtml({ title: texts.verifySubject, subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody, btnText: texts.verifyBtn, btnUrl: null, code, lang }),
        });
        console.log('\n📧 VERIFY CODE for', normalizedEmail, ':', code, '(expires in 10 min)\n');
      } catch (e) {
        console.error('Email failed:', e.message);
      }
    })();
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') return res.status(400).json({ error: 'This email is already registered. Please log in or use a different email.' });
    console.error(err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  } finally {
    client.release();
  }
});

// VERIFY EMAIL
router.post('/verify-email', validate(schemas.verifyEmail), async (req, res) => {
  try {
    const { email, code } = req.validatedBody;

    const userResult = await pool.query('SELECT id, email_verified FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid email address.' });
    }
    if (userResult.rows[0].email_verified) {
      return res.status(400).json({ error: 'This email is already verified. Please log in.' });
    }

    const otpResult = await verifyOtp(email, 'email_verification', code);
    if (!otpResult.valid) {
      if (otpResult.error === 'too_many_attempts') {
        return res.status(429).json({ error: 'Too many failed attempts. This verification code has been locked. Please request a new one.' });
      }
      if (otpResult.error === 'invalid_or_expired') {
        return res.status(400).json({ error: 'This code has expired or is no longer valid. Please request a new one.' });
      }
      return res.status(400).json({ error: 'Incorrect code. Please try again.' });
    }

    await pool.query('UPDATE users SET email_verified = TRUE WHERE email = $1', [email]);

    res.json({ message: '✅ Email verified successfully! You can now log in.' });
  } catch (err) {
    console.error('Verify email error:', err.message);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// RESEND VERIFICATION
router.post('/resend-verification', validate(schemas.resendVerification), async (req, res) => {
  try {
    const { email } = req.validatedBody;
    const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

    if (result.rows.length === 0) {
      return res.json({ message: 'If this email is registered, a verification code will be sent.' });
    }

    const user = result.rows[0];
    if (user.email_verified) {
      return res.json({ message: 'If this email is registered, a verification code will be sent.' });
    }

    const limit = await checkOtpRateLimit(email);
    if (!limit.allowed) {
      if (limit.reason === 'hourly_limit') {
        return res.status(429).json({ error: 'Too many verification attempts. Please try again in 1 hour.' });
      }
      return res.status(429).json({ error: `Please wait ${formatWaitTime(limit.waitSeconds)} before requesting another code.` });
    }

    const lang = getLang(user.preferred_language);
    const code = generateOtp();
    await storeOtp(email, 'email_verification', code);

    res.json({ message: 'If this email is registered, a verification code has been sent.' });

    const texts = emailTexts[lang];
    (async () => {
      try {
        await sendEmail({
          from: process.env.FROM_EMAIL || process.env.SMTP_USER,
          to: email,
          subject: texts.verifySubject,
          html: emailHtml({ title: texts.verifySubject, subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody, btnText: texts.verifyBtn, btnUrl: null, code, lang }),
        });
        console.log('\n📧 RESEND VERIFY CODE for', email, ':', code, '(expires in 10 min)\n');
      } catch (e) {
        console.error('Email failed:', e.message);
      }
    })();
  } catch (err) {
    console.error('Resend verification error:', err.message);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// LOGIN
router.post('/login', loginIpLimiter, async (req, res) => {
  try {
    const email = sanitizeString(req.body.email, 255).toLowerCase();
    const password = req.body.password;

    const lockout = await checkLoginLockout(email);
    if (!lockout.allowed) {
      return res.status(429).json({
        error: `Too many failed attempts. Please try again in ${lockout.waitMin} minutes.`
      });
    }

    const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);
    if (result.rows.length === 0) {
      return res.status(400).json({ error: 'Email or password is incorrect. Please try again.' });
    }

    const user = result.rows[0];

    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      const attempts = await recordFailedLogin(email);
      if (attempts.locked_until) {
        const now = await serverNow();
        const waitMin = Math.ceil((new Date(attempts.locked_until) - now) / 60000);
        return res.status(429).json({
          error: `Too many failed attempts. Account locked for ${waitMin} minutes.`
        });
      }
      return res.status(400).json({ error: 'Email or password is incorrect. Please try again.' });
    }

    if (!user.email_verified) {
      return res.status(403).json({ error: 'Please verify your email before logging in. Check your inbox for the verification code.' });
    }

    await clearLoginAttempts(email);

    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    res.json({
      token,
      user: {
        id: user.id,
        full_name: user.full_name,
        email: user.email,
        role: user.role
      }
    });
  } catch (err) {
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// GUEST LOGIN
router.post('/guest-login', async (req, res) => {
  try {
    const guestId = 'guest_' + crypto.randomBytes(16).toString('hex');
    const token = jwt.sign(
      { userId: guestId, email: null, role: 'guest' },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    res.json({
      token,
      user: {
        id: guestId,
        full_name: 'Guest',
        email: null,
        role: 'guest'
      }
    });
  } catch (err) {
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// FORGOT PASSWORD
router.post('/forgot-password', validate(schemas.forgotPassword), async (req, res) => {
  try {
    const { email } = req.validatedBody;
    const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

    if (result.rows.length === 0) {
      return res.json({ message: 'If this email is registered, a reset code will be sent.' });
    }

    const limit = await checkOtpRateLimit(email);
    if (!limit.allowed) {
      if (limit.reason === 'hourly_limit') {
        return res.status(429).json({ error: 'You\'ve requested too many reset codes. Please try again in 1 hour.' });
      }
      return res.status(429).json({ error: `Please wait ${formatWaitTime(limit.waitSeconds)} before requesting another code.` });
    }

    const user = result.rows[0];
    const lang = getLang(user.preferred_language);

    const code = generateOtp();
    await storeOtp(email, 'password_reset', code);

    res.json({ message: 'If this email is registered, a reset code has been sent.' });

    const texts = emailTexts[lang];
    (async () => {
      try {
        await sendEmail({
          from: process.env.FROM_EMAIL || process.env.SMTP_USER,
          to: email,
          subject: texts.resetSubject,
          html: emailHtml({ title: texts.resetSubject, subtitle: texts.resetSubtitle, bodyContent: texts.resetBody, btnText: null, btnUrl: null, code, lang }),
        });
        console.log('\n🔑 RESET CODE for', email, ':', code, '(expires in 10 min)\n');
      } catch (e) {
        console.error('❌ Reset email failed:', e.message);
      }
    })();
  } catch (err) {
    console.error('❌ Forgot password error:', err.message);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// RESET PASSWORD
router.post('/reset-password', validate(schemas.resetPassword), async (req, res) => {
  try {
    const { email, code, new_password } = req.validatedBody;

    const strength = validatePasswordStrength(new_password);
    if (!strength.valid) {
      return res.status(400).json({ error: strength.error });
    }

    const otpResult = await verifyOtp(email, 'password_reset', code);
    if (!otpResult.valid) {
      if (otpResult.error === 'too_many_attempts') {
        return res.status(429).json({ error: 'Too many failed attempts. This code has been locked for your security. Please request a new reset code.' });
      }
      if (otpResult.error === 'invalid_or_expired') {
        return res.status(400).json({ error: 'This code has expired or is no longer valid. Please request a new one.' });
      }
      return res.status(400).json({ error: 'Incorrect code. Please try again.' });
    }

    const userResult = await pool.query('SELECT password_hash FROM users WHERE email=$1', [email]);
    if (userResult.rows.length > 0) {
      const isSamePassword = await bcrypt.compare(new_password, userResult.rows[0].password_hash);
      if (isSamePassword) {
        return res.status(400).json({ error: 'New password cannot be the same as your previous password. Please choose a different password.' });
      }
    }

    const hashed = await bcrypt.hash(new_password, 10);
    await pool.query('UPDATE users SET password_hash=$1 WHERE email=$2', [hashed, email]);

    res.json({ message: 'Your password has been updated. You can now log in.' });
  } catch (err) {
    console.error('❌ Reset password error:', err.message);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

module.exports = router;