const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const translationsPath = path.join(root, 'lib', 'lang', 'translations.dart');
let src = fs.readFileSync(translationsPath, 'utf8');

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

function parseLangBlock(lang) {
  const blockRe = new RegExp(`'${lang}':\\s*\\{([\\s\\S]*?)\\n  \\},`);
  const match = src.match(blockRe);
  if (!match) return { keys: {}, raw: '' };
  const keys = {};
  const lineRe = /'([a-z][a-z0-9_]*)':\s*'((?:\\'|[^'])*)'/g;
  let m;
  while ((m = lineRe.exec(match[1]))) keys[m[1]] = m[2];
  return { keys, raw: match[1] };
}

const enBlock = parseLangBlock('en');
const allLangs = {};
for (const lang of langs) allLangs[lang] = parseLangBlock(lang);

// Load supplemental translations from JSON if present
const supplementalPath = path.join(__dirname, 'translation_supplement.json');
const supplemental = fs.existsSync(supplementalPath)
  ? JSON.parse(fs.readFileSync(supplementalPath, 'utf8'))
  : {};

function escapeDart(str) {
  return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

for (const lang of langs) {
  const missing = [...used].filter((k) => !allLangs[lang].keys[k]).sort();
  if (missing.length === 0) continue;

  const additions = [];
  for (const key of missing) {
    let value =
      supplemental[lang]?.[key] ??
      (lang === 'en' ? supplemental.en?.[key] : null) ??
      allLangs.ar.keys[key] ??
      enBlock.keys[key] ??
      key;
    additions.push(`    '${key}': '${escapeDart(value)}',`);
  }

  const blockRe = new RegExp(`('${lang}':\\s*\\{)([\\s\\S]*?)(\\n  \\},)`);
  src = src.replace(blockRe, (_, open, body, close) => {
    const trimmed = body.replace(/\s+$/, '');
    const joiner = trimmed.endsWith(',') || trimmed.trim() === '' ? '\n' : ',\n';
    return `${open}${trimmed}${joiner}${additions.join('\n')}${close}`;
  });

  console.log(`Patched ${lang}: +${missing.length} keys`);
}

fs.writeFileSync(translationsPath, src, 'utf8');
console.log('Done.');
