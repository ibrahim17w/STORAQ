//middleware/emails.js
const nodemailer = require('nodemailer');
const { emailTexts, getLang } = require('../config/constants');

let transporter = null;
let emailReady = false;

if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '587'),
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  emailReady = true;
}

async function sendEmail({ from, to, subject, html }) {
  const sender = from || process.env.FROM_EMAIL || process.env.SMTP_USER;
  if (!emailReady || !transporter) {
    throw new Error('SMTP not configured. Check .env file.');
  }
  return await transporter.sendMail({ from: sender, to, subject, html });
}

if (emailReady) {
  transporter.verify((err, success) => {
    if (err) console.error('❌ SMTP connection failed:', err.message);
    else console.log('✅ SMTP Ready (Gmail)');
  });
} else {
  console.warn('⚠️ No SMTP configured. Set SMTP_HOST, SMTP_USER, SMTP_PASS in .env');
}

function emailHtml({ title, subtitle, bodyContent, btnText, btnUrl, code, lang }) {
  const isRTL = ['ar', 'ur', 'he', 'fa'].includes(lang);
  const dir = isRTL ? 'rtl' : 'ltr';

  return `
<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);margin:0;padding:40px 20px;color:#333;direction:${dir};min-height:100vh;box-sizing:border-box;}
.wrapper{max-width:600px;margin:0 auto;}
.container{background:#fff;padding:40px;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,0.3);text-align:center;}
.logo{font-size:32px;font-weight:800;color:#667eea;margin-bottom:8px;}
.tagline{font-size:14px;color:#888;margin-bottom:30px;}
h1{color:#2c3e50;font-size:26px;margin:0 0 8px 0;}
h2{color:#555;font-size:17px;margin:0 0 20px 0;font-weight:400;}
p{line-height:1.7;font-size:16px;color:#555;margin:0 0 20px 0;}
.btn{display:inline-block;padding:14px 32px;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:16px;margin:10px 0;transition:transform 0.2s;}
.btn:hover{transform:translateY(-2px);}
.code-box{background:linear-gradient(135deg,#f5f7fa 0%,#e4e8ec 100%);border:2px dashed #667eea;border-radius:12px;padding:24px;margin:20px 0;display:inline-block;min-width:200px;}
.code{font-size:36px;font-weight:800;letter-spacing:8px;color:#667eea;font-family:'Courier New',monospace;}
.code-label{font-size:12px;color:#888;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px;}
.timer{font-size:13px;color:#e74c3c;margin-top:8px;font-weight:500;}
.divider{height:1px;background:#e0e0e0;margin:24px 0;}
.footer{margin-top:30px;font-size:12px;color:#999;line-height:1.6;}
.security-tips{background:#f8f9fa;border-radius:8px;padding:16px;margin-top:20px;text-align:${isRTL ? 'right' : 'left'};}
.security-tips h3{font-size:13px;color:#555;margin:0 0 8px 0;text-transform:uppercase;letter-spacing:1px;}
.security-tips ul{margin:0;padding-${isRTL ? 'right' : 'left'}:20px;font-size:12px;color:#777;}
.security-tips li{margin-bottom:4px;}
</style>
</head>
<body>
<div class="wrapper">
<div class="container">
<div class="logo">🔗 STORAQ</div>
<div class="tagline">${subtitle}</div>
<h1>${title}</h1>
<p>${bodyContent}</p>
${btnUrl ? `<a href="${btnUrl}" class="btn">${btnText}</a>` : ''}
${code ? `<div class="code-box"><div class="code-label">${isRTL ? 'رمز التحقق' : (lang === 'zh' ? '验证码' : (lang === 'ru' ? 'Код подтверждения' : 'Verification Code'))}</div><div class="code">${code}</div><div class="timer">⏱ ${isRTL ? 'ينتهي خلال 10 دقائق' : (lang === 'zh' ? '10分钟后过期' : (lang === 'ru' ? 'Истекает через 10 минут' : 'Expires in 10 minutes'))}</div></div>` : ''}
<div class="divider"></div>
<div class="security-tips">
<h3>${isRTL ? 'نصائح الأمان' : (lang === 'zh' ? '安全提示' : (lang === 'ru' ? 'Советы безопасности' : 'Security Tips'))}</h3>
<ul>
<li>${isRTL ? 'لا تشارك هذا الرمز مع أي شخص' : (lang === 'zh' ? '请勿与任何人分享此验证码' : (lang === 'ru' ? 'Никому не сообщайте этот код' : 'Never share this code with anyone'))}</li>
<li>${isRTL ? 'سيتم إلغاء الرمز بعد 3 محاولات خاطئة' : (lang === 'zh' ? '3次错误尝试后代码将失效' : (lang === 'ru' ? 'Код будет отменен после 3 неудачных попыток' : 'Code will be cancelled after 3 wrong attempts'))}</li>
<li>${isRTL ? 'إذا لم تطلب هذا، يمكنك تجاهل البريد بأمان' : (lang === 'zh' ? '如果您没有请求此操作，可以安全忽略此邮件' : (lang === 'ru' ? 'Если вы не запрашивали это, просто проигнорируйте письмо' : 'If you didn\'t request this, you can safely ignore this email'))}</li>
</ul>
</div>
<div class="footer">
${isRTL ? 'إذا لم تطلب هذا، يمكنك تجاهل البريد بأمان.' : (lang === 'zh' ? '如果您没有请求此操作，可以安全忽略此邮件。' : (lang === 'ru' ? 'Если вы не запрашивали это, просто проигнорируйте письмо.' : 'If you didn\'t request this, you can safely ignore this email.'))}<br>
© ${new Date().getFullYear()} STORAQ. ${isRTL ? 'جميع الحقوق محفوظة.' : (lang === 'zh' ? '保留所有权利。' : (lang === 'ru' ? 'Все права защищены.' : 'All rights reserved.'))}
</div>
</div>
</div>
</body>
</html>
`;
}

module.exports = { transporter, emailReady, sendEmail, emailHtml };
