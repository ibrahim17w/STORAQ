//config/constants.js
require('dotenv').config();
const { GoogleGenerativeAI } = require('@google/generative-ai');

const PORT = process.env.PORT || 3000;
const genAI = process.env.GEMINI_API_KEY ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY) : null;

const emailTexts = {
  en: {
    verifySubject: 'Verify your Market Bridge account',
    verifySubtitle: 'Welcome aboard!',
    verifyBody: 'Thank you for joining Market Bridge! Please enter the verification code below in your app to verify your email address and activate your account.',
    verifyBtn: null,
    resetSubject: 'Your password reset code',
    resetSubtitle: 'Password Reset Request',
    resetBody: 'We received a request to reset your password. Use the code below to complete the process.',
    resetBtn: null,
  },
  ar: {
    verifySubject: 'تأكيد حسابك على Market Bridge',
    verifySubtitle: 'مرحباً بك!',
    verifyBody: 'شكراً لانضمامك إلى Market Bridge! أدخل رمز التحقق أدناه في التطبيق لتأكيد بريدك الإلكتروني وتفعيل حسابك.',
    verifyBtn: null,
    resetSubject: 'رمز إعادة تعيين كلمة المرور',
    resetSubtitle: 'طلب إعادة تعيين كلمة المرور',
    resetBody: 'تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك. استخدم الرمز أدناه لإكمال العملية.',
    resetBtn: null,
  },
  fr: {
    verifySubject: 'Vérifiez votre compte Market Bridge',
    verifySubtitle: 'Bienvenue !',
    verifyBody: 'Merci d\'avoir rejoint Market Bridge ! Saisissez le code de vérification ci-dessous dans votre application pour vérifier votre adresse e-mail et activer votre compte.',
    verifyBtn: null,
    resetSubject: 'Votre code de réinitialisation',
    resetSubtitle: 'Demande de réinitialisation',
    resetBody: 'Nous avons reçu une demande de réinitialisation de votre mot de passe. Utilisez le code ci-dessous pour compléter le processus.',
    resetBtn: null,
  },
  es: {
    verifySubject: 'Verifica tu cuenta de Market Bridge',
    verifySubtitle: '¡Bienvenido!',
    verifyBody: '¡Gracias por unirte a Market Bridge! Introduce el código de verificación a continuación en tu aplicación para verificar tu correo y activar tu cuenta.',
    verifyBtn: null,
    resetSubject: 'Tu código de restablecimiento',
    resetSubtitle: 'Solicitud de restablecimiento',
    resetBody: 'Recibimos una solicitud para restablecer tu contraseña. Usa el código de abajo para completar el proceso.',
    resetBtn: null,
  },
  tr: {
    verifySubject: 'Market Bridge hesabınızı doğrulayın',
    verifySubtitle: 'Hoş geldiniz!',
    verifyBody: 'Market Bridge\'e katıldığınız için teşekkürler! E-posta adresinizi doğrulamak ve hesabınızı etkinleştirmek için uygulamaya aşağıdaki doğrulama kodunu girin.',
    verifyBtn: null,
    resetSubject: 'Şifre sıfırlama kodunuz',
    resetSubtitle: 'Şifre Sıfırlama Talebi',
    resetBody: 'Şifrenizi sıfırlama talebi aldık. İşlemi tamamlamak için aşağıdaki kodu kullanın.',
    resetBtn: null,
  },
  ur: {
    verifySubject: 'Market Bridge اکاؤنٹ کی تصدیق',
    verifySubtitle: 'خوش آمدید!',
    verifyBody: 'Market Bridge میں شامل ہونے کا شکریہ! اپنا ای میل تصدیق کرنے اور اکاؤنٹ فعال کرنے کے لیے ایپ میں نیچے دیا گیا تصدیقی کوڈ درج کریں۔',
    verifyBtn: null,
    resetSubject: 'پاس ورڈ ری سیٹ کوڈ',
    resetSubtitle: 'پاس ورڈ ری سیٹ کی درخواست',
    resetBody: 'ہمیں آپ کا پاس ورڈ ری سیٹ کرنے کی درخواست موصول ہوئی ہے۔ عمل مکمل کرنے کے لیے نیچے دیا گیا کوڈ استعمال کریں۔',
    resetBtn: null,
  },
  hi: {
    verifySubject: 'अपना Market Bridge खाता सत्यापित करें',
    verifySubtitle: 'स्वागत है!',
    verifyBody: 'Market Bridge में शामिल होने के लिए धन्यवाद! अपना ईमेल सत्यापित करने और खाता सक्रिय करने के लिए ऐप में नीचे दिया गया सत्यापन कोड दर्ज करें।',
    verifyBtn: null,
    resetSubject: 'आपका पासवर्ड रीसेट कोड',
    resetSubtitle: 'पासवर्ड रीसेट अनुरोध',
    resetBody: 'हमें आपका पासवर्ड रीसेट करने का अनुरोध प्राप्त हुआ। प्रक्रिया पूरी करने के लिए नीचे दिए कोड का उपयोग करें।',
    resetBtn: null,
  },
  bn: {
    verifySubject: 'আপনার Market Bridge অ্যাকাউন্ট যাচাই করুন',
    verifySubtitle: 'স্বাগতম!',
    verifyBody: 'Market Bridge-এ যোগ দেওয়ার জন্য ধন্যবাদ! আপনার ইমেইল যাচাই করতে এবং অ্যাকাউন্ট সক্রিয় করতে অ্যাপে নীচের যাচাইকরণ কোডটি লিখুন।',
    verifyBtn: null,
    resetSubject: 'আপনার পাসওয়ার্ড রিসেট কোড',
    resetSubtitle: 'পাসওয়ার্ড রিসেট অনুরোধ',
    resetBody: 'আমরা আপনার পাসওয়ার্ড রিসেট করার অনুরোধ পেয়েছি। প্রক্রিয়া সম্পূর্ণ করতে নীচের কোডটি ব্যবহার করুন।',
    resetBtn: null,
  },
  ru: {
    verifySubject: 'Подтвердите аккаунт Market Bridge',
    verifySubtitle: 'Добро пожаловать!',
    verifyBody: 'Спасибо за регистрацию в Market Bridge! Введите код подтверждения ниже в приложении, чтобы подтвердить адрес электронной почты и активировать аккаунт.',
    verifyBtn: null,
    resetSubject: 'Код сброса пароля',
    resetSubtitle: 'Запрос на сброс пароля',
    resetBody: 'Мы получили запрос на сброс вашего пароля. Используйте код ниже для завершения процесса.',
    resetBtn: null,
  },
  zh: {
    verifySubject: '验证您的 Market Bridge 账户',
    verifySubtitle: '欢迎！',
    verifyBody: '感谢加入 Market Bridge！请在应用中输入下方的验证码以验证您的电子邮件地址并激活账户。',
    verifyBtn: null,
    resetSubject: '您的密码重置验证码',
    resetSubtitle: '密码重置请求',
    resetBody: '我们收到了重置您密码的请求。请使用下方验证码完成操作。',
    resetBtn: null,
  },
};

function getLang(userLang) {
  return emailTexts[userLang] ? userLang : 'en';
}

module.exports = { PORT, genAI, emailTexts, getLang };
