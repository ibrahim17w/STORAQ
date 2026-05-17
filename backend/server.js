require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const multer = require('multer');
const path = require('path');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');

const app = express();

const PORT = process.env.PORT || 3000;

// SECURITY FIX: Dynamic base URL that works with tunnels (localtunnel, ngrok, cloudflare)
// Uses request headers to detect the public URL, falls back to env var or localhost
function getBaseUrl(req) {
  const forwardedProto = req.headers['x-forwarded-proto'];
  const forwardedHost = req.headers['x-forwarded-host'];
  
  if (forwardedProto && forwardedHost) {
    return `${forwardedProto}://${forwardedHost}`;
  }
  
  return process.env.BASE_URL || `http://localhost:${PORT}`;
}

// SECURITY FIX: Allow all origins for temporary tunnel testing
app.use(cors({
  origin: ['https://market-bridge-baug.onrender.com', 'http://localhost:3000'],
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use('/uploads', express.static('uploads'));

// IP-level rate limiter (20 requests per 15 min per IP)
const authLimiter = rateLimit({
 windowMs: 15 * 60 * 1000,
 max: 20,
 standardHeaders: true,
 legacyHeaders: false,
 handler: (req, res) => res.status(429).json({ error: 'Too many requests. Please try again later.' }),
});
app.use('/api/auth/', authLimiter);

// Strict login IP limiter (5 attempts per IP per 15 min)
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

const pool = new Pool({
 user: process.env.DB_USER,
 host: process.env.DB_HOST,
 database: process.env.DB_NAME,
 password: process.env.DB_PASSWORD,
 port: process.env.DB_PORT,
});

const transporter = nodemailer.createTransport({
 host: process.env.SMTP_HOST,
 port: process.env.SMTP_PORT,
 secure: process.env.SMTP_SECURE === 'true',
 auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});

transporter.verify((err) => {
 if (err) console.error('❌ SMTP Failed:', err.message);
 else console.log('✅ SMTP Ready');
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

// ==================== HELPERS ====================
// SECURITY FIX: Input sanitization to prevent injection and DB bloat
function sanitizeString(str, maxLen = 255) {
 if (typeof str !== 'string') return '';
 return str.trim().substring(0, maxLen);
}

function isValidEmail(email) {
 return /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/.test(email);
}

// ==================== SERVER TIME (DB / Internet Clock) ====================
async function serverNow() {
 const result = await pool.query('SELECT NOW() as now');
 return new Date(result.rows[0].now);
}

// ==================== PASSWORD STRENGTH VALIDATOR ====================
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
 const seqNums = ['012','123','234','345','456','567','678','789','890'];
 for (const seq of seqNums) if (pwd.includes(seq)) { score -= 2; break; }

 const seqLet = ['abc','bcd','cde','def','efg','fgh','ghi','hij','ijk','jkl','klm','lmn','mno','nop','opq','pqr','qrs','rst','stu','tuv','uvw','vwx','wxy','xyz'];
 for (const seq of seqLet) if (lowerPwd.includes(seq)) { score -= 2; break; }

 if (pwd.length >= 6) {
 for (let i = 0; i <= pwd.length - 6; i++) {
 const chunk = pwd.substring(i, i + 3);
 if (pwd.substring(i + 3).includes(chunk)) { score -= 2; break; }
 }
 }

 const weakPatterns = ['qwerty','asdf','zxcv','password','letmein','admin','123456','111111','000000'];
 for (const pattern of weakPatterns) if (lowerPwd.includes(pattern)) { score -= 3; break; }

 const typeCount = [/^[A-Z]/.test('A') ? /[A-Z]/.test(pwd) : false, /[a-z]/.test(pwd), /[0-9]/.test(pwd), /[^A-Za-z0-9]/.test(pwd)].filter(Boolean).length;
 if (typeCount < 3) score -= 1;

 if (score <= 2) return { valid: false, error: 'Password is too weak. Use 8+ chars with uppercase, lowercase, number, and symbol. Avoid patterns like 123, abc, or repeated words.' };
 if (score <= 4) return { valid: false, error: 'Password is medium strength. Make it stronger with more variety and length.' };
 return { valid: true };
}

// ==================== DATABASE-PERSISTED BRUTE FORCE ====================
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
 const result = await pool.query(
 `INSERT INTO failed_logins (email, count, locked_until, last_attempt)
 VALUES ($1, 1, NULL, $2)
 ON CONFLICT (email) DO UPDATE SET
 count = failed_logins.count + 1,
 last_attempt = $2,
 locked_until = CASE
 WHEN failed_logins.count + 1 >= 15 THEN $2 + INTERVAL '2 hours'
 WHEN failed_logins.count + 1 >= 10 THEN $2 + INTERVAL '30 minutes'
 WHEN failed_logins.count + 1 >= 5 THEN $2 + INTERVAL '5 minutes'
 ELSE failed_logins.locked_until
 END
 RETURNING count, locked_until`,
 [email, now]
 );

 return result.rows[0];
}

async function clearLoginAttempts(email) {
 await pool.query('DELETE FROM failed_logins WHERE email = $1', [email]);
}

// ==================== RESET PASSWORD RATE LIMITING (DB-based) ====================
// SECURITY FIX: Eliminated SQL injection by using make_interval() instead of string interpolation
async function checkResetRateLimit(email, maxAttempts = 3, windowHours = 1, cooldownSeconds = 60) {
 const result = await pool.query(
 `SELECT COUNT(*) as c, MAX(created_at) as last
 FROM password_resets
 WHERE email = $1 AND created_at > NOW() - make_interval(hours => $2)`,
 [email, windowHours]
 );

 const count = parseInt(result.rows[0].c);
 const lastAttempt = result.rows[0].last ? new Date(result.rows[0].last) : null;
 const now = await serverNow();

 if (lastAttempt) {
 const secondsSinceLast = (now - lastAttempt) / 1000;
 if (secondsSinceLast < cooldownSeconds) {
 const waitSeconds = Math.ceil(cooldownSeconds - secondsSinceLast);
 return { allowed: false, waitSeconds };
 }
 }

 if (count >= maxAttempts) {
 return { allowed: false, waitSeconds: 3600 };
 }

 return { allowed: true };
}

// ==================== EMAIL TEMPLATES ====================
function emailHtml({ title, subtitle, bodyContent, btnText, btnUrl, code, lang }) {
 const isRTL = ['ar','ur','he','fa'].includes(lang);
 const dir = isRTL ? 'rtl' : 'ltr';

 return `
<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${title}</title>
<style>body{font-family:Arial,sans-serif;background:#f4f4f4;padding:20px;color:#333;direction:${dir};}.container{max-width:600px;margin:0 auto;background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);text-align:center;}h1{color:#2c3e50;font-size:24px;}h2{color:#555;font-size:18px;margin-top:10px;}p{line-height:1.6;font-size:16px;}.btn{display:inline-block;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:5px;font-weight:bold;margin-top:20px;}.code{font-size:28px;font-weight:bold;letter-spacing:4px;color:#2c3e50;background:#ecf0f1;padding:15px;border-radius:5px;display:inline-block;margin:15px 0;}.footer{margin-top:30px;font-size:12px;color:#999;}</style>
</head>
<body><div class="container"><h1>${title}</h1><h2>${subtitle}</h2><p>${bodyContent}</p>${btnUrl ? `<a href="${btnUrl}" class="btn">${btnText}</a>` : ''}${code ? `<div class="code">${code}</div>` : ''}<div class="footer">If you didn't request this, you can safely ignore this email.</div></div></body></html>
`;
}

const emailTexts = {
 en: {
 verifySubject: 'Verify your Market Bridge account',
 verifySubtitle: 'Welcome aboard!',
 verifyBody: (url) => `
Thank you for joining Market Bridge! Please click the button below to verify your email address and activate your account.
<br><br>
Or copy this link: ${url}
`,
 verifyBtn: 'Verify My Email',
 resetSubject: 'Your password reset code',
 resetSubtitle: 'Password Reset Request',
 resetBody: `
We received a request to reset your password. Use the code below to complete the process. This code expires in 10 minutes.
`,
 resetBtn: null,
 },
 ar: {
 verifySubject: 'تأكيد حسابك على Market Bridge',
 verifySubtitle: 'مرحباً بك!',
 verifyBody: (url) => `
شكراً لانضمامك إلى Market Bridge! اضغط الزر أدناه لتأكيد بريدك الإلكتروني وتفعيل حسابك.
<br><br>
أو انسخ هذا الرابط: ${url}
`,
 verifyBtn: 'تأكيد بريدي الإلكتروني',
 resetSubject: 'رمز إعادة تعيين كلمة المرور',
 resetSubtitle: 'طلب إعادة تعيين كلمة المرور',
 resetBody: `
تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك. استخدم الرمز أدناه لإكمال العملية. ينتهي صلاحية هذا الرمز خلال 10 دقائق.
`,
 resetBtn: null,
 },
 fr: {
 verifySubject: 'Vérifiez votre compte Market Bridge',
 verifySubtitle: 'Bienvenue !',
 verifyBody: (url) => `
Merci d'avoir rejoint Market Bridge ! Cliquez sur le bouton ci-dessous pour vérifier votre adresse e-mail et activer votre compte.
<br><br>
Ou copiez ce lien : ${url}
`,
 verifyBtn: 'Vérifier mon e-mail',
 resetSubject: 'Votre code de réinitialisation',
 resetSubtitle: 'Demande de réinitialisation',
 resetBody: `
Nous avons reçu une demande de réinitialisation de votre mot de passe. Utilisez le code ci-dessous pour compléter le processus. Ce code expire dans 10 minutes.
`,
 resetBtn: null,
 },
 es: {
 verifySubject: 'Verifica tu cuenta de Market Bridge',
 verifySubtitle: '¡Bienvenido!',
 verifyBody: (url) => `
¡Gracias por unirte a Market Bridge! Haz clic en el botón de abajo para verificar tu correo y activar tu cuenta.
<br><br>
O copia este enlace: ${url}
`,
 verifyBtn: 'Verificar mi correo',
 resetSubject: 'Tu código de restablecimiento',
 resetSubtitle: 'Solicitud de restablecimiento',
 resetBody: `
Recibimos una solicitud para restablecer tu contraseña. Usa el código de abajo para completar el proceso. Este código expira en 10 minutos.
`,
 resetBtn: null,
 },
 tr: {
 verifySubject: 'Market Bridge hesabınızı doğrulayın',
 verifySubtitle: 'Hoş geldiniz!',
 verifyBody: (url) => `
Market Bridge'e katıldığınız için teşekkürler! E-posta adresinizi doğrulamak ve hesabınızı etkinleştirmek için aşağıdaki düğmeye tıklayın.
<br><br>
Veya bu bağlantıyı kopyalayın: ${url}
`,
 verifyBtn: 'E-postamı Doğrula',
 resetSubject: 'Şifre sıfırlama kodunuz',
 resetSubtitle: 'Şifre Sıfırlama Talebi',
 resetBody: `
Şifrenizi sıfırlama talebi aldık. İşlemi tamamlamak için aşağıdaki kodu kullanın. Bu kod 10 dakika içinde geçersiz olacaktır.
`,
 resetBtn: null,
 },
 ur: {
 verifySubject: 'Market Bridge اکاؤنٹ کی تصدیق',
 verifySubtitle: 'خوش آمدید!',
 verifyBody: (url) => `
Market Bridge میں شامل ہونے کا شکریہ! اپنا ای میل تصدیق کرنے اور اکاؤنٹ فعال کرنے کے لیے نیچے کے بٹن پر کلک کریں۔
<br><br>
یا یہ لنک کاپی کریں: ${url}
`,
 verifyBtn: 'ای میل تصدیق کریں',
 resetSubject: 'پاس ورڈ ری سیٹ کوڈ',
 resetSubtitle: 'پاس ورڈ ری سیٹ کی درخواست',
 resetBody: `
ہمیں آپ کا پاس ورڈ ری سیٹ کرنے کی درخواست موصول ہوئی ہے۔ عمل مکمل کرنے کے لیے نیچے دیا گیا کوڈ استعمال کریں۔ یہ کوڈ 10 منٹ میں ختم ہو جائے گا۔`,
 resetBtn: null,
 },
 hi: {
 verifySubject: 'अपना Market Bridge खाता सत्यापित करें',
 verifySubtitle: 'स्वागत है!',
 verifyBody: (url) => `
Market Bridge में शामिल होने के लिए धन्यवाद! अपना ईमेल सत्यापित करने और खाता सक्रिय करने के लिए नीचे दिए बटन पर क्लिक करें।
<br><br>
या इस लिंक को कॉपी करें: ${url}
`,
 verifyBtn: 'मेरा ईमेल सत्यापित करें',
 resetSubject: 'आपका पासवर्ड रीसेट कोड',
 resetSubtitle: 'पासवर्ड रीसेट अनुरोध',
 resetBody: `
हमें आपका पासवर्ड रीसेट करने का अनुरोध प्राप्त हुआ। प्रक्रिया पूरी करने के लिए नीचे दिए कोड का उपयोग करें। यह कोड 10 मिनट में समाप्त हो जाएगा।
`,
 resetBtn: null,
 },
 bn: {
 verifySubject: 'আপনার Market Bridge অ্যাকাউন্ট যাচাই করুন',
 verifySubtitle: 'স্বাগতম!',
 verifyBody: (url) => `
Market Bridge-এ যোগ দেওয়ার জন্য ধন্যবাদ! আপনার ইমেইল যাচাই করতে এবং অ্যাকাউন্ট সক্রিয় করতে নীচের বোতামে ক্লিক করুন।
<br><br>
অথবা এই লিঙ্কটি কপি করুন: ${url}
`,
 verifyBtn: 'আমার ইমেইল যাচাই করুন',
 resetSubject: 'আপনার পাসওয়ার্ড রিসেট কোড',
 resetSubtitle: 'পাসওয়ার্ড রিসেট অনুরোধ',
 resetBody: `
আমরা আপনার পাসওয়ার্ড রিসেট করার অনুরোধ পেয়েছি। প্রক্রিয়া সম্পূর্ণ করতে নীচের কোডটি ব্যবহার করুন। এই কোড ১০ মিনিটের মধ্যে মেয়াদ শেষ হবে।
`,
 resetBtn: null,
 },
 ru: {
 verifySubject: 'Подтвердите аккаунт Market Bridge',
 verifySubtitle: 'Добро пожаловать!',
 verifyBody: (url) => `
Спасибо за регистрацию в Market Bridge! Нажмите кнопку ниже, чтобы подтвердить адрес электронной почты и активировать аккаунт.
<br><br>
Или скопируйте ссылку: ${url}
`,
 verifyBtn: 'Подтвердить почту',
 resetSubject: 'Код сброса пароля',
 resetSubtitle: 'Запрос на сброс пароля',
 resetBody: `
Мы получили запрос на сброс вашего пароля. Используйте код ниже для завершения процесса. Код действителен 10 минут.
`,
 resetBtn: null,
 },
 zh: {
 verifySubject: '验证您的 Market Bridge 账户',
 verifySubtitle: '欢迎！',
 verifyBody: (url) => `
感谢加入 Market Bridge！请点击下方按钮验证您的电子邮件地址并激活账户。
<br><br>
或复制此链接：${url}
`,
 verifyBtn: '验证我的邮箱',
 resetSubject: '您的密码重置验证码',
 resetSubtitle: '密码重置请求',
 resetBody: `
我们收到了重置您密码的请求。请使用下方验证码完成操作。此验证码将在10分钟后过期。
`,
 resetBtn: null,
 },
};

function getLang(userLang) {
 return emailTexts[userLang] ? userLang : 'en';
}

// Multer
// SECURITY FIX: Added file type validation so only images can be uploaded
const storage = multer.diskStorage({
 destination: (req, file, cb) => cb(null, 'uploads/'),
 filename: (req, file, cb) => {
 const unique = Date.now() + '-' + Math.round(Math.random() * 1e9);
 cb(null, unique + path.extname(file.originalname));
 },
});
const upload = multer({
 storage,
 limits: { fileSize: 5 * 1024 * 1024 },
 fileFilter: (req, file, cb) => {
 const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
 const allowedExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
 const ext = path.extname(file.originalname).toLowerCase();

 // FIX: Flutter sometimes sends application/octet-stream instead of the real mimetype.
 // Trust the file extension as a fallback.
 const isAllowedType = allowedTypes.includes(file.mimetype);
 const isAllowedExt = allowedExts.includes(ext);
 const isOctetStream = file.mimetype === 'application/octet-stream';

 if (isAllowedType || (isOctetStream && isAllowedExt)) {
 cb(null, true);
 } else {
 cb(new Error(`Unsupported file type (${file.mimetype || 'unknown'}). Only JPEG, PNG, WebP, and GIF images are allowed.`));
 }
 }
});

app.get('/', (req, res) => res.send('Market Bridge API'));

// REGISTER
app.post('/api/auth/register', async (req, res) => {
 const client = await pool.connect();
 try {
 await client.query('BEGIN');

 // SECURITY FIX: Sanitize all user inputs
 const full_name = sanitizeString(req.body.full_name, 100);
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const phone = sanitizeString(req.body.phone, 50);
 const password = req.body.password;
 const role = req.body.role;
 const store = req.body.store;
 const preferred_language = sanitizeString(req.body.preferred_language, 10) || 'en';

 if (!isValidEmail(email)) {
 return res.status(400).json({ error: 'Please enter a valid email address.' });
 }

 const allowedRoles = ['store_owner', 'customer'];
 const userRole = allowedRoles.includes(role) ? role : 'customer';
 const lang = getLang(preferred_language);
 const hashedPassword = await bcrypt.hash(password, 10);
 const verifyToken = crypto.randomBytes(32).toString('hex');

 const userResult = await client.query(
 'INSERT INTO users (full_name, email, phone, password_hash, role, verification_token, preferred_language) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, full_name, email, role',
 [full_name, email, phone, hashedPassword, userRole, verifyToken, lang]
 );

 if (userRole === 'store_owner' && store) {
 await client.query(
 'INSERT INTO stores (name, city, village, country, lat, lng, phone, owner_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
 [
   sanitizeString(store.name, 100),
   sanitizeString(store.city, 100),
   sanitizeString(store.village, 100),
   sanitizeString(store.country, 100) || 'Syria',
   store.lat,
   store.lng,
   sanitizeString(store.phone, 50),
   userResult.rows[0].id
 ]
 );
 }
 await client.query('COMMIT');

 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL for tunnel support
 const verifyUrl = `${getBaseUrl(req)}/api/auth/verify-email?token=${verifyToken}`;
 const texts = emailTexts[lang];

 try {
 await transporter.sendMail({
 from: `"Market Bridge" <${process.env.SMTP_FROM || 'noreply@marketbridge.com'}>`,
 to: email,
 subject: texts.verifySubject,
 html: emailHtml({ title: 'Market Bridge', subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody(verifyUrl), btnText: texts.verifyBtn, btnUrl: verifyUrl, lang }),
 });
 } catch (e) {
 console.error('Email failed:', e.message);
 }

 console.log('\n📧 VERIFY LINK:', verifyUrl, '\n');
 res.status(201).json({ message: 'Created. Check email.', verify_url: verifyUrl });
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
// SECURITY FIX: Validate token format before hitting the database
app.get('/api/auth/verify-email', async (req, res) => {
 const { token } = req.query;
 if (!token || typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) {
 return res.status(400).send('<h2>Invalid or expired link</h2>');
 }
 const result = await pool.query('UPDATE users SET email_verified=TRUE, verification_token=NULL WHERE verification_token=$1 RETURNING id', [token]);
 if (result.rowCount === 0) return res.status(400).send('<h2>Invalid or expired link</h2>');
 res.send('<h2>✅ Verified! You can now log in.</h2>');
});

// SECURITY FIX: Added missing resend-verification endpoint that your Flutter app calls
app.post('/api/auth/resend-verification', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

 // Opaque response: same message whether email exists or not
 if (result.rows.length === 0) {
 return res.json({ message: 'If this email is registered, a verification email will be sent.' });
 }

 const user = result.rows[0];
 if (user.email_verified) {
 return res.json({ message: 'If this email is registered, a verification email will be sent.' });
 }

 const lang = getLang(user.preferred_language);
 const verifyToken = crypto.randomBytes(32).toString('hex');
 await pool.query('UPDATE users SET verification_token=$1 WHERE id=$2', [verifyToken, user.id]);

 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL
 const verifyUrl = `${getBaseUrl(req)}/api/auth/verify-email?token=${verifyToken}`;
 const texts = emailTexts[lang];

 try {
 await transporter.sendMail({
 from: `"Market Bridge" <${process.env.SMTP_FROM || 'noreply@marketbridge.com'}>`,
 to: email,
 subject: texts.verifySubject,
 html: emailHtml({ title: 'Market Bridge', subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody(verifyUrl), btnText: texts.verifyBtn, btnUrl: verifyUrl, lang }),
 });
 } catch (e) {
 console.error('Email failed:', e.message);
 }

 res.json({ message: 'If this email is registered, a verification email will be sent.' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// LOGIN — DB-persisted brute force + IP limiter
// SECURITY FIX: Reordered checks to prevent email enumeration
app.post('/api/auth/login', loginIpLimiter, async (req, res) => {
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
 // SECURITY FIX: Do NOT record failed login for non-existent emails (prevents DB bloat / DoS)
 return res.status(400).json({ error: 'Email or password is incorrect. Please try again.' });
 }

 const user = result.rows[0];

 // SECURITY FIX: Check password BEFORE email_verified to prevent enumeration
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

 // Only reached if password was correct
 if (!user.email_verified) {
 return res.status(403).json({ error: 'Please verify your email before logging in. Check your inbox for the verification link.' });
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

// FORGOT PASSWORD — DB rate limiting + 10 min expiry
app.post('/api/auth/forgot-password', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

 // SECURITY FIX: Return opaque 200 for non-existent emails to prevent enumeration
 if (result.rows.length === 0) {
 return res.json({ message: 'If this email is registered, a reset code will be sent.' });
 }

 const limit = await checkResetRateLimit(email, 3, 1, 60);
 if (!limit.allowed) {
 return res.status(429).json({
 error: limit.waitSeconds > 60
 ? `Too many attempts. Please try again in ${Math.ceil(limit.waitSeconds / 60)} minutes.`
 : `Please wait ${limit.waitSeconds} seconds before requesting another code.`
 });
 }

 const user = result.rows[0];
 const lang = getLang(user.preferred_language);

 // SECURITY FIX: Cryptographically secure 6-digit code
 const code = crypto.randomInt(100000, 999999).toString();
 const now = await serverNow();
 const expires = new Date(now.getTime() + 10 * 60 * 1000);

 await pool.query(
 'INSERT INTO password_resets (email, reset_code, expires_at, created_at) VALUES ($1,$2,$3,$4)',
 [email, code, expires, now]
 );

 const texts = emailTexts[lang];
 try {
 await transporter.sendMail({
 from: `"Market Bridge" <${process.env.SMTP_FROM || 'noreply@marketbridge.com'}>`,
 to: email,
 subject: texts.resetSubject,
 html: emailHtml({ title: 'Market Bridge', subtitle: texts.resetSubtitle, bodyContent: texts.resetBody, btnText: null, btnUrl: null, code, lang }),
 });
 } catch (e) {
 console.error('❌ Reset email failed:', e.message);
 await pool.query('DELETE FROM password_resets WHERE email=$1 AND reset_code=$2', [email, code]);
 return res.status(500).json({ error: 'Failed to send email. Please check your SMTP settings or try again later.' });
 }

 console.log('\n🔑 RESET CODE for', email, ':', code, '(expires in 10 min)\n');
 res.json({ message: 'If this email is registered, a reset code has been sent.' });
 } catch (err) {
 console.error('❌ Forgot password error:', err.message);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// RESET PASSWORD — strength check + 10 min expiry validation
// CHANGE: Added check to prevent reusing the same old password
app.post('/api/auth/reset-password', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const code = req.body.code;
 const new_password = req.body.new_password;

 const strength = validatePasswordStrength(new_password);
 if (!strength.valid) {
 return res.status(400).json({ error: strength.error });
 }

 const now = await serverNow();
 const result = await pool.query(
 'SELECT * FROM password_resets WHERE email=$1 AND reset_code=$2 AND used=FALSE AND expires_at > $3 ORDER BY id DESC LIMIT 1',
 [email, code, now]
 );
 if (result.rows.length === 0) {
 return res.status(400).json({ error: 'This code is invalid or has expired. Please request a new one.' });
 }

 // CHANGE: Prevent password reuse — compare new password against current hash
 const userResult = await pool.query('SELECT password_hash FROM users WHERE email=$1', [email]);
 if (userResult.rows.length > 0) {
 const isSamePassword = await bcrypt.compare(new_password, userResult.rows[0].password_hash);
 if (isSamePassword) {
 return res.status(400).json({ error: 'New password cannot be the same as your previous password. Please choose a different password.' });
 }
 }

 const hashed = await bcrypt.hash(new_password, 10);
 await pool.query('UPDATE users SET password_hash=$1 WHERE email=$2', [hashed, email]);
 await pool.query('UPDATE password_resets SET used=TRUE WHERE id=$1', [result.rows[0].id]);

 res.json({ message: 'Your password has been updated. You can now log in.' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET CURRENT USER
app.get('/api/me', authenticateToken, async (req, res) => {
 const result = await pool.query(
 'SELECT id, full_name, email, phone, role, preferred_language, created_at FROM users WHERE id=$1',
 [req.user.userId]
 );
 if (result.rows.length === 0) return res.status(404).json({ error: 'Account not found' });
 res.json(result.rows[0]);
});

// UPDATE PROFILE
// FIX: Return only safe fields (exclude password_hash)
app.put('/api/me', authenticateToken, async (req, res) => {
 const full_name = sanitizeString(req.body.full_name, 100);
 const phone = sanitizeString(req.body.phone, 50);
 const result = await pool.query(
 'UPDATE users SET full_name=$1, phone=$2 WHERE id=$3 RETURNING id, full_name, email, phone, role, preferred_language, created_at',
 [full_name, phone, req.user.userId]
 );
 res.json(result.rows[0]);
});

// CHANGE PASSWORD
// FIX: Validate fields exist before hashing + enforce strength
app.put('/api/me/password', authenticateToken, async (req, res) => {
 try {
 const { current_password, new_password } = req.body;
 if (!current_password || !new_password) {
 return res.status(400).json({ error: 'Current password and new password are required.' });
 }

 const strength = validatePasswordStrength(new_password);
 if (!strength.valid) {
 return res.status(400).json({ error: strength.error });
 }

 const user = await pool.query('SELECT password_hash FROM users WHERE id=$1', [req.user.userId]);
 if (!await bcrypt.compare(current_password, user.rows[0].password_hash)) {
 return res.status(400).json({ error: 'Current password is incorrect' });
 }
 const hashed = await bcrypt.hash(new_password, 10);
 await pool.query('UPDATE users SET password_hash=$1 WHERE id=$2', [hashed, req.user.userId]);
 res.json({ message: 'Password updated successfully' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// DELETE ACCOUNT
// SECURITY FIX: Clean up all related data instead of orphaning it
app.delete('/api/me', authenticateToken, async (req, res) => {
 const client = await pool.connect();
 try {
 await client.query('BEGIN');

 // Delete user's products first (via their store)
 const storeResult = await client.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 for (const row of storeResult.rows) {
 await client.query('DELETE FROM products WHERE store_id=$1', [row.id]);
 }

 // Delete user's store
 await client.query('DELETE FROM stores WHERE owner_id=$1', [req.user.userId]);

 // Clean up auth artifacts and tracking tables
 const userResult = await client.query('SELECT email FROM users WHERE id=$1', [req.user.userId]);
 if (userResult.rows.length > 0) {
 const email = userResult.rows[0].email;
 await client.query('DELETE FROM failed_logins WHERE email=$1', [email]);
 await client.query('DELETE FROM password_resets WHERE email=$1', [email]);
 }
 await client.query('DELETE FROM product_views WHERE user_id=$1', [req.user.userId]);
 await client.query('DELETE FROM search_queries WHERE user_id=$1', [req.user.userId]);

 // Delete user
 await client.query('DELETE FROM users WHERE id=$1', [req.user.userId]);
 await client.query('COMMIT');
 res.json({ message: 'Account deleted successfully' });
 } catch (err) {
 await client.query('ROLLBACK');
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 } finally {
 client.release();
 }
});

// TRACK PRODUCT VIEW
app.post('/api/products/:id/view', async (req, res) => {
 try {
 const productId = parseInt(req.params.id);
 if (isNaN(productId)) return res.status(400).json({ error: 'Invalid product ID' });

 // Increment view count
 await pool.query(
 'UPDATE products SET view_count = COALESCE(view_count, 0) + 1 WHERE id = $1',
 [productId]
 );

 // Log view if user is authenticated
 const authHeader = req.headers['authorization'];
 if (authHeader) {
 const token = authHeader.split(' ')[1];
 try {
 const decoded = jwt.verify(token, process.env.JWT_SECRET);
 await pool.query(
 'INSERT INTO product_views (product_id, user_id, viewed_at) VALUES ($1, $2, NOW())',
 [productId, decoded.userId]
 );
 } catch (_) {
 // Invalid token, just count the view
 }
 }

 res.json({ message: 'View tracked' });
 } catch (err) {
 console.error('Track view error:', err);
 res.status(500).json({ error: 'Something went wrong' });
 }
});

// TRACK SEARCH QUERY
app.post('/api/search/track', async (req, res) => {
 try {
 const query = sanitizeString(req.body.query, 200);
 if (!query || query.length < 2) {
 return res.status(400).json({ error: 'Query too short' });
 }

 // Log search query
 const authHeader = req.headers['authorization'];
 let userId = null;
 if (authHeader) {
 const token = authHeader.split(' ')[1];
 try {
 const decoded = jwt.verify(token, process.env.JWT_SECRET);
 userId = decoded.userId;
 } catch (_) {}
 }

 await pool.query(
 'INSERT INTO search_queries (query, user_id, searched_at) VALUES ($1, $2, NOW())',
 [query.toLowerCase(), userId]
 );

 res.json({ message: 'Search tracked' });
 } catch (err) {
 console.error('Track search error:', err);
 res.status(500).json({ error: 'Something went wrong' });
 }
});

// GET TRENDING PRODUCTS (most viewed)
app.get('/api/products/trending', async (req, res) => {
 try {
 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.view_count,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
 LIMIT 20`
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Trending error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET SPONSORED STORES
app.get('/api/stores/sponsored', async (req, res) => {
 try {
 const now = await serverNow();
 const result = await pool.query(
 `SELECT id, name, city, country, image_url, lat, lng, sponsorship_tier
 FROM stores
 WHERE is_sponsored = TRUE
 AND (sponsorship_expires_at IS NULL OR sponsorship_expires_at > $1)
 ORDER BY sponsorship_tier DESC, RANDOM()
 LIMIT 10`,
 [now]
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Sponsored error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET PERSONALIZED RECOMMENDATIONS (requires auth)
app.get('/api/recommendations', authenticateToken, async (req, res) => {
 try {
 const userId = req.user.userId;
 const now = await serverNow();
 const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

 // Get user's recent views and searches
 const viewsResult = await pool.query(
 `SELECT DISTINCT p.name, p.store_id
 FROM product_views pv
 JOIN products p ON pv.product_id = p.id
 WHERE pv.user_id = $1 AND pv.viewed_at > $2
 LIMIT 20`,
 [userId, sevenDaysAgo]
 );

 const searchesResult = await pool.query(
 `SELECT DISTINCT query FROM search_queries
 WHERE user_id = $1 AND searched_at > $2
 LIMIT 10`,
 [userId, sevenDaysAgo]
 );

 // Build recommendation query based on user behavior
 let query = `
 SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
 s.id as shop_id, s.name as shop_name, s.city, s.country
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 `;

 const params = [];
 const conditions = [];

 // Add conditions based on viewed products (same store)
 if (viewsResult.rows.length > 0) {
 const storeIds = [...new Set(viewsResult.rows.map(r => r.store_id).filter(Boolean))];
 if (storeIds.length > 0) {
 params.push(...storeIds);
 conditions.push(`s.id IN (${storeIds.map((_, i) => '$' + (params.length - storeIds.length + i + 1)).join(',')})`);
 }
 }

 // Add conditions based on search queries
 if (searchesResult.rows.length > 0) {
 const searchTerms = searchesResult.rows.map(r => r.query);
 for (const term of searchTerms) {
 params.push('%' + term + '%');
 conditions.push(`(p.name ILIKE $${params.length} OR p.description ILIKE $${params.length})`);
 }
 }

 if (conditions.length > 0) {
 query += ' AND (' + conditions.join(' OR ') + ')';
 }

 query += ' ORDER BY p.created_at DESC LIMIT 20';

 const result = await pool.query(query, params);

 // If no personalized results, return popular items
 if (result.rows.length === 0) {
 const fallback = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
 LIMIT 20`
 );
 return res.json(fallback.rows);
 }

 res.json(result.rows);
 } catch (err) {
 console.error('Recommendations error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.get('/api/stores', async (req, res) => {
 const result = await pool.query('SELECT * FROM stores');
 res.json(result.rows);
});

app.get('/api/stores/:id', async (req, res) => {
 const result = await pool.query('SELECT * FROM stores WHERE id=$1', [req.params.id]);
 if (result.rows.length === 0) return res.status(404).json({ error: 'Store not found' });
 res.json(result.rows[0]);
});

// MY STORE
app.get('/api/my-store', authenticateToken, async (req, res) => {
 const result = await pool.query('SELECT * FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (result.rows.length === 0) return res.status(404).json({ error: 'No store found' });
 res.json(result.rows[0]);
});

// PRODUCTS
app.get('/api/products/:storeId', async (req, res) => {
 const result = await pool.query('SELECT * FROM products WHERE store_id=$1 ORDER BY created_at DESC', [req.params.storeId]);
 res.json(result.rows);
});

app.post('/api/products', authenticateToken, upload.single('image'), async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(403).json({ error: 'You do not own a store' });
 const storeId = storeResult.rows[0].id;
 const { name, price, quantity, description, barcode } = req.body;

 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL
 const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : null;
 const result = await pool.query(
 'INSERT INTO products (store_id, name, price, quantity, description, barcode, image_url) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *',
 [storeId, name, price, quantity || 0, description, barcode, imageUrl]
 );
 res.status(201).json(result.rows[0]);
 } catch (err) {
 console.error(err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.put('/api/products/:id', authenticateToken, upload.single('image'), async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });
 const storeId = storeResult.rows[0].id;
 const { name, price, quantity, description, barcode } = req.body;
 const existing = await pool.query('SELECT * FROM products WHERE id=$1 AND store_id=$2', [req.params.id, storeId]);
 if (existing.rows.length === 0) return res.status(404).json({ error: 'Product not found' });

 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL
 const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : existing.rows[0].image_url;
 const result = await pool.query(
 'UPDATE products SET name=$1, price=$2, quantity=$3, description=$4, barcode=$5, image_url=$6, updated_at=NOW() WHERE id=$7 RETURNING *',
 [name, price, quantity, description, barcode, imageUrl, req.params.id]
 );
 res.json(result.rows[0]);
 } catch (err) {
 console.error(err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.delete('/api/products/:id', authenticateToken, async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });
 const storeId = storeResult.rows[0].id;
 await pool.query('DELETE FROM products WHERE id=$1 AND store_id=$2', [req.params.id, storeId]);
 res.json({ message: 'Product deleted successfully' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.post('/api/upload', authenticateToken, upload.single('image'), (req, res) => {
 if (!req.file) return res.status(400).json({ error: 'No image uploaded' });

 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL
 res.json({ url: `${getBaseUrl(req)}/uploads/${req.file.filename}` });
});

// UPDATE PREFERRED LANGUAGE
app.put('/api/me/language', authenticateToken, async (req, res) => {
 try {
 const preferred_language = sanitizeString(req.body.preferred_language, 10);
 await pool.query(
 'UPDATE users SET preferred_language=$1 WHERE id=$2',
 [preferred_language, req.user.userId]
 );
 res.json({ message: 'Language preference updated' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// ==================== MARKETPLACE FEED ====================
app.get('/api/marketplace/feed', async (req, res) => {
 try {
 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.created_at DESC
 LIMIT 50`
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Feed error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// UPDATE MY STORE
app.put('/api/my-store', authenticateToken, upload.single('image'), async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT * FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store found' });

 const existing = storeResult.rows[0];
 const name = req.body.name !== undefined ? sanitizeString(req.body.name, 100) : existing.name;
 const city = req.body.city !== undefined ? sanitizeString(req.body.city, 100) : existing.city;
 const village = req.body.village !== undefined ? sanitizeString(req.body.village, 100) : existing.village;
 const country = req.body.country !== undefined ? sanitizeString(req.body.country, 100) : existing.country;
 const phone = req.body.phone !== undefined ? sanitizeString(req.body.phone, 50) : existing.phone;
 const lat = req.body.lat !== undefined ? parseFloat(req.body.lat) : existing.lat;
 const lng = req.body.lng !== undefined ? parseFloat(req.body.lng) : existing.lng;
 // FIX: Use dynamic getBaseUrl(req) instead of hardcoded BASE_URL
 const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : existing.image_url;

 const result = await pool.query(
 `UPDATE stores SET name=$1, city=$2, village=$3, country=$4, phone=$5, lat=$6, lng=$7, image_url=$8, updated_at=NOW() WHERE id=$9 RETURNING *`,
 [name, city, village, country, phone, lat, lng, imageUrl, existing.id]
 );
 res.json(result.rows[0]);
 } catch (err) {
 console.error(err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});


// ==================== NEARBY PRODUCTS (GEO FILTER) ====================
app.get('/api/marketplace/nearby', async (req, res) => {
 try {
 const lat = parseFloat(req.query.lat);
 const lng = parseFloat(req.query.lng);
 const radiusKm = parseFloat(req.query.radius) || 15;

 if (isNaN(lat) || isNaN(lng)) {
 return res.status(400).json({ error: 'lat and lng query params are required' });
 }

 // Haversine formula in SQL (Earth radius ≈ 6371 km)
 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng,
 (6371 * acos(
 cos(radians($1)) * cos(radians(s.lat)) *
 cos(radians(s.lng) - radians($2)) +
 sin(radians($1)) * sin(radians(s.lat))
 )) AS distance_km
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 AND s.lat IS NOT NULL AND s.lng IS NOT NULL
 HAVING (6371 * acos(
 cos(radians($1)) * cos(radians(s.lat)) *
 cos(radians(s.lng) - radians($2)) +
 sin(radians($1)) * sin(radians(s.lat))
 )) <= $3
 ORDER BY distance_km ASC
 LIMIT 50`,
 [lat, lng, radiusKm]
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Nearby error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// ==================== NEW: ANALYTICS & HOME SCREEN ENDPOINTS ====================

// ADMIN: Set store as sponsored (protected endpoint)
app.put('/api/admin/stores/:id/sponsor', authenticateToken, async (req, res) => {
 try {
 // Check if user is admin
 const userResult = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
 if (userResult.rows.length === 0 || userResult.rows[0].role !== 'admin') {
 return res.status(403).json({ error: 'Admin access required' });
 }

 const storeId = parseInt(req.params.id);
 const { tier, expiresAt } = req.body;

 await pool.query(
 `UPDATE stores
 SET is_sponsored = TRUE,
 sponsorship_tier = $1,
 sponsorship_expires_at = $2
 WHERE id = $3`,
 [tier || 1, expiresAt || null, storeId]
 );

 res.json({ message: 'Store sponsorship updated' });
 } catch (err) {
 console.error('Sponsor error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// FIX: Multer error handler — file rejections return 400 instead of crashing with 500
app.use((err, req, res, next) => {
 if (err instanceof multer.MulterError) {
 if (err.code === 'LIMIT_FILE_SIZE') {
 return res.status(400).json({ error: 'File too large. Max 5MB.' });
 }
 return res.status(400).json({ error: err.message });
 }
 if (err && err.message && err.message.includes('Only JPEG')) {
 return res.status(400).json({ error: err.message });
 }
 next(err);
});

app.listen(PORT, '0.0.0.0', () => console.log(`Server on ${getBaseUrl({ headers: {} })} (port ${PORT})`));