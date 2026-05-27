//middleware/security.js
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const { pool } = require('../config/database');
const { serverNow } = require('./helpers');

function validatePasswordStrength(pwd) {
  if (!pwd || pwd.length < 8) return { valid: false, error: 'Password must be at least 8 characters' };

  let score = 0;
  if (pwd.length >= 8) score++;
  if (pwd.length >= 12) score++;
  if (pwd.length >= 16) score++;
  if (/[A-Z]/.test(pwd)) score++;
  if (/[a-z]/.test(pwd)) score++;
  if (/[0-9]/.test(pwd)) score++;
  if (/[^A-Za-z0-9]/.test(pwd)) score++;

  const lowerPwd = pwd.toLowerCase();
  const seqNums = ['012', '123', '234', '345', '456', '567', '678', '789', '890'];
  for (const seq of seqNums) if (pwd.includes(seq)) { score -= 2; break; }

  const seqLet = ['abc', 'bcd', 'cde', 'def', 'efg', 'fgh', 'ghi', 'hij', 'ijk', 'jkl', 'klm', 'lmn', 'mno', 'nop', 'opq', 'pqr', 'qrs', 'rst', 'stu', 'tuv', 'uvw', 'vwx', 'wxy', 'xyz'];
  for (const seq of seqLet) if (lowerPwd.includes(seq)) { score -= 2; break; }

  if (pwd.length >= 6) {
    for (let i = 0; i <= pwd.length - 6; i++) {
      const chunk = pwd.substring(i, i + 3);
      if (pwd.substring(i + 3).includes(chunk)) { score -= 2; break; }
    }
  }

  const weakPatterns = ['qwerty', 'asdf', 'zxcv', 'password', 'letmein', 'admin', '123456', '111111', '000000'];
  for (const pattern of weakPatterns) if (lowerPwd.includes(pattern)) { score -= 3; break; }

  const typeCount = [/[A-Z]/.test(pwd), /[a-z]/.test(pwd), /[0-9]/.test(pwd), /[^A-Za-z0-9]/.test(pwd)].filter(Boolean).length;
  if (typeCount < 3) score -= 1;

  if (score <= 2) return { valid: false, error: 'Password is too weak. Use 8+ chars with uppercase, lowercase, number, and symbol. Avoid patterns like 123, abc, or repeated words.' };
  if (score <= 4) return { valid: false, error: 'Password is medium strength. Make it stronger with more variety and length.' };
  return { valid: true };
}

async function checkLoginLockout(email) {
  const result = await pool.query(
    'SELECT count, locked_until FROM failed_logins WHERE email = $1',
    [email]
  );

  if (result.rows.length === 0) return { allowed: true, waitMin: 0 };

  const row = result.rows[0];
  const now = await serverNow();

  if (row.locked_until && new Date(row.locked_until) > now) {
    const waitMs = new Date(row.locked_until) - now;
    const waitMin = Math.ceil(waitMs / 60000);
    return { allowed: false, waitMin };
  }

  return { allowed: true, waitMin: 0 };
}

async function recordFailedLogin(email) {
  const now = await serverNow();
  const lock2h = new Date(now.getTime() + 2 * 60 * 60 * 1000);
  const lock30m = new Date(now.getTime() + 30 * 60 * 1000);
  const lock5m = new Date(now.getTime() + 5 * 60 * 1000);

  const result = await pool.query(
    `INSERT INTO failed_logins (email, count, locked_until, last_attempt)
     VALUES ($1, 1, NULL, $2)
     ON CONFLICT (email) DO UPDATE SET
       count = failed_logins.count + 1,
       last_attempt = $2,
       locked_until = CASE
         WHEN failed_logins.count + 1 >= 15 THEN $3
         WHEN failed_logins.count + 1 >= 10 THEN $4
         WHEN failed_logins.count + 1 >= 5  THEN $5
         ELSE failed_logins.locked_until
       END
     RETURNING count, locked_until`,
    [email, now, lock2h, lock30m, lock5m]
  );

  return result.rows[0];
}

async function clearLoginAttempts(email) {
  await pool.query('DELETE FROM failed_logins WHERE email = $1', [email]);
}

async function checkOtpRateLimit(email) {
  const now = await serverNow();
  const sixtySecondsAgo = new Date(now.getTime() - 60 * 1000);
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

  const cooldownResult = await pool.query(
    `SELECT MAX(created_at) as last FROM verification_codes
     WHERE email = $1 AND created_at > $2`,
    [email, sixtySecondsAgo]
  );
  const lastAttempt = cooldownResult.rows[0].last ? new Date(cooldownResult.rows[0].last) : null;
  if (lastAttempt) {
    const secondsSinceLast = (now - lastAttempt) / 1000;
    if (secondsSinceLast < 60) {
      const waitSeconds = Math.ceil(60 - secondsSinceLast);
      return { allowed: false, waitSeconds, reason: 'cooldown' };
    }
  }

  const hourResult = await pool.query(
    `SELECT COUNT(*) as c FROM verification_codes
     WHERE email = $1 AND created_at > $2`,
    [email, oneHourAgo]
  );
  const count = parseInt(hourResult.rows[0].c);
  if (count >= 5) {
    return { allowed: false, waitSeconds: 3600, reason: 'hourly_limit' };
  }

  return { allowed: true };
}

function generateOtp() {
  return crypto.randomInt(100000, 999999).toString();
}

async function storeOtp(email, type, code) {
  const now = await serverNow();
  const expires = new Date(now.getTime() + 10 * 60 * 1000);
  const codeHash = await bcrypt.hash(code, 10);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE verification_codes SET used = TRUE, invalidated_at = $1
       WHERE email = $2 AND type = $3 AND used = FALSE`,
      [now, email, type]
    );
    await client.query(
      `INSERT INTO verification_codes (email, type, code_hash, expires_at, created_at, attempts, used)
       VALUES ($1, $2, $3, $4, $5, 0, FALSE)`,
      [email, type, codeHash, expires, now]
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function verifyOtp(email, type, inputCode) {
  const now = await serverNow();

  const result = await pool.query(
    `SELECT id, code_hash, attempts, used, expires_at
     FROM verification_codes
     WHERE email = $1 AND type = $2 AND used = FALSE AND expires_at > $3
     ORDER BY created_at DESC LIMIT 1`,
    [email, type, now]
  );

  if (result.rows.length === 0) {
    return { valid: false, error: 'invalid_or_expired' };
  }

  const record = result.rows[0];

  if (record.attempts >= 3) {
    await pool.query(
      'UPDATE verification_codes SET used = TRUE WHERE id = $1',
      [record.id]
    );
    return { valid: false, error: 'too_many_attempts' };
  }

  await pool.query(
    'UPDATE verification_codes SET attempts = attempts + 1 WHERE id = $1',
    [record.id]
  );

  const isMatch = await bcrypt.compare(inputCode, record.code_hash);

  if (!isMatch) {
    const updated = await pool.query(
      'SELECT attempts FROM verification_codes WHERE id = $1',
      [record.id]
    );
    if (updated.rows[0].attempts >= 3) {
      await pool.query(
        'UPDATE verification_codes SET used = TRUE WHERE id = $1',
        [record.id]
      );
      return { valid: false, error: 'too_many_attempts' };
    }
    return { valid: false, error: 'invalid_code' };
  }

  await pool.query(
    'UPDATE verification_codes SET used = TRUE, verified_at = $1 WHERE id = $2',
    [now, record.id]
  );

  return { valid: true };
}

module.exports = {
  validatePasswordStrength,
  checkLoginLockout,
  recordFailedLogin,
  clearLoginAttempts,
  checkOtpRateLimit,
  generateOtp,
  storeOtp,
  verifyOtp
};
