//config/upload.js
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');

const uploadsDir = path.join(process.cwd(), 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const unique = Date.now() + '-' + crypto.randomBytes(8).toString('hex');
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

const productUpload = upload.fields([
  { name: 'image', maxCount: 1 },
  { name: 'extra_images', maxCount: 5 }
]);

function cleanupUploadedFiles(req) {
  if (!req.files && !req.file) return;
  const files = req.files ? Object.values(req.files).flat() : [req.file];
  for (const file of files) {
    if (file?.path) {
      fs.unlink(file.path, (err) => {
        if (err) console.error('Failed to cleanup uploaded file:', err.message);
      });
    }
  }
}

module.exports = { uploadsDir, upload, productUpload, cleanupUploadedFiles };
