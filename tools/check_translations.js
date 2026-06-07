const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const translationsPath = path.join(root, 'lib', 'lang', 'translations.dart');
const src = fs.readFileSync(translationsPath, 'utf8');

const used = new Set();
const re = /t\('([a-z][a-z0-9_]*)'\)/g;

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p);
    else if (entry.name.endsWith('.dart')) {
      const content = fs.readFileSync(p, 'utf8');
      let m;
      while ((m = re.exec(content))) used.add(m[1]);
    }
  }
}

walk(path.join(root, 'lib'));

const langs = ['en', 'ar', 'fr', 'es', 'tr', 'ur', 'hi', 'bn', 'ru', 'zh'];
const langMaps = {};

for (const lang of langs) {
  const blockRe = new RegExp(`'${lang}':\\s*\\{([\\s\\S]*?)\\n  \\},`);
  const match = src.match(blockRe);
  const keys = new Set();
  if (match) {
    const keyRe = /'([a-z][a-z0-9_]*)':/g;
    let k;
    while ((k = keyRe.exec(match[1]))) keys.add(k[1]);
  }
  langMaps[lang] = keys;
}

const missingEn = [...used].filter((k) => !langMaps.en.has(k)).sort();
console.log('USED_KEYS', used.size);
console.log('EN_DEFINED', langMaps.en.size);
console.log('MISSING_IN_EN', missingEn.length);
for (const k of missingEn) console.log('  ' + k);

for (const lang of langs.filter((l) => l !== 'en')) {
  const missing = [...used].filter((k) => !langMaps[lang].has(k));
  console.log(`MISSING_IN_${lang.toUpperCase()}`, missing.length);
  if (missing.length && missing.length <= 40) {
    for (const k of missing.sort()) console.log('  ' + k);
  }
}
