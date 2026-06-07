const assert = require('node:assert/strict');
const test = require('node:test');

const {
  generateOtp,
  validatePasswordStrength,
} = require('../middleware/security');

test('generateOtp returns a six-digit code', () => {
  const code = generateOtp();

  assert.match(code, /^\d{6}$/);
});

test('validatePasswordStrength rejects short passwords', () => {
  const result = validatePasswordStrength('A1!');

  assert.equal(result.valid, false);
  assert.match(result.error, /at least 8 characters/i);
});

test('validatePasswordStrength rejects common weak patterns', () => {
  const result = validatePasswordStrength('Password123!');

  assert.equal(result.valid, false);
  assert.match(result.error, /weak|medium/i);
});

test('validatePasswordStrength accepts a varied strong password', () => {
  const result = validatePasswordStrength('R9$vL2!qM8pZ');

  assert.equal(result.valid, true);
});
