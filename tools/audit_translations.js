const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const translationsPath = path.join(root, 'lib', 'lang', 'translations.dart');
const legalPath = path.join(root, 'lib', 'lang', 'legal_policies.dart');
let src = fs.readFileSync(translationsPath, 'utf8');

// Also count legal policy keys merged at runtime
const legalSrc = fs.readFileSync(legalPath, 'utf8');
const legalKeyRe = /'([a-z][a-z0-9_]*)':/g;
const legalKeys = new Set();
let lm;
while ((lm = legalKeyRe.exec(legalSrc))) legalKeys.add(lm[1]);

const used = new Set();
const usedAt = {};
const re = /t\('([a-z][a-z0-9_]*)'\)/g;

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p);
    else if (entry.name.endsWith('.dart')) {
      const rel = path.relative(root, p).replace(/\\/g, '/');
      const content = fs.readFileSync(p, 'utf8');
      let m;
      while ((m = re.exec(content))) {
        used.add(m[1]);
        if (!usedAt[m[1]]) usedAt[m[1]] = [];
        if (!usedAt[m[1]].includes(rel)) usedAt[m[1]].push(rel);
      }
    }
  }
}
walk(path.join(root, 'lib'));

const langs = ['en', 'ar', 'fr', 'es', 'tr', 'ur', 'hi', 'bn', 'ru', 'zh'];

function parseLang(lang) {
  const blockRe = new RegExp(`'${lang}':\\s*\\{([\\s\\S]*?)\\n  \\},`);
  const match = src.match(blockRe);
  const keys = {};
  if (!match) return keys;
  const body = match[1];
  const multi = /'([a-z][a-z0-9_]*)':\s*'''([\s\S]*?)'''/g;
  const single = /'([a-z][a-z0-9_]*)':\s*'((?:\\'|[^'])*)'/g;
  let m;
  while ((m = multi.exec(body))) keys[m[1]] = m[2];
  while ((m = single.exec(body))) if (!(m[1] in keys)) keys[m[1]] = m[2];
  return keys;
}

const en = parseLang('en');
for (const k of legalKeys) {
  if (!en[k]) en[k] = `[legal:${k}]`;
}

const missingEn = [...used].filter((k) => !en[k]).sort();
console.log('USED_KEYS', used.size);
console.log('MISSING_IN_EN', missingEn.length);
for (const k of missingEn) {
  console.log(`  ${k}  ← ${usedAt[k].slice(0, 3).join(', ')}`);
}

const chatKeys = [
  'messages', 'no_messages_yet', 'chat_from_store', 'start_conversation',
  'type_message', 'report_chat', 'delete_chat_confirm', 'delete',
  'cancel', 'report', 'retry', 'store',
];

console.log('\n--- CHAT KEYS BY LANGUAGE ---');
for (const lang of langs) {
  const m = parseLang(lang);
  for (const k of legalKeys) {
    if (!m[k]) m[k] = en[k];
  }
  const missing = chatKeys.filter((k) => !m[k]);
  const empty = chatKeys.filter((k) => m[k] === '');
  const sameEn = chatKeys.filter((k) => m[k] && en[k] && m[k] === en[k] && lang !== 'en');
  if (missing.length || empty.length || (lang !== 'en' && sameEn.length)) {
    console.log(`${lang}: missing=[${missing.join(',')}] empty=[${empty.join(',')}] untranslated=[${sameEn.join(',')}]`);
  }
}

console.log('\n--- ALL LANGUAGES SUMMARY ---');
for (const lang of langs) {
  const m = parseLang(lang);
  for (const k of legalKeys) {
    if (!m[k]) m[k] = en[k];
  }
  const missing = [...used].filter((k) => !m[k]).sort();
  const empty = [...used].filter((k) => m[k] === '').sort();
  const sameEn = [...used].filter(
    (k) => m[k] && en[k] && m[k] === en[k] && lang !== 'en' && !k.startsWith('tier_')
  ).sort();
  console.log(`${lang}: missing=${missing.length} empty=${empty.length} same_as_en=${sameEn.length}`);
  if (missing.length) console.log('  missing:', missing.join(', '));
  if (empty.length) console.log('  empty:', empty.join(', '));
  if (lang === 'zh' && sameEn.length) {
    console.log('  untranslated (zh):', sameEn.slice(0, 30).join(', '));
    if (sameEn.length > 30) console.log('  ...+' + (sameEn.length - 30) + ' more');
  }
}

// Hardcoded English in UI (simple heuristic)
const hardcoded = [];
function walkHard(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walkHard(p);
    else if (entry.name.endsWith('.dart') && !p.includes('translations.dart') && !p.includes('legal_policies')) {
      const rel = path.relative(root, p).replace(/\\/g, '/');
      const lines = fs.readFileSync(p, 'utf8').split('\n');
      lines.forEach((line, i) => {
        if (line.includes('t(')) return;
        const m = line.match(/(?:Text|title|label|hintText|tooltip|SnackBar)\s*\(?\s*['"]([A-Za-z][^'"]{2,60})['"]/);
        if (m && !m[1].includes('\$') && !m[1].startsWith('http')) {
          hardcoded.push({ file: rel, line: i + 1, text: m[1] });
        }
      });
    }
  }
}
walkHard(path.join(root, 'lib'));
console.log('\n--- HARDCODED ENGLISH STRINGS (no t()) ---');
console.log('count:', hardcoded.length);
for (const h of hardcoded.slice(0, 40)) {
  console.log(`  ${h.file}:${h.line}  "${h.text}"`);
}
if (hardcoded.length > 40) console.log(`  ... and ${hardcoded.length - 40} more`);
