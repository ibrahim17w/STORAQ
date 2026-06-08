const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'lib', 'lang', 'translations.dart'), 'utf8');
const used = new Set();
const re = /t\('([a-z][a-z0-9_]*)'\)/g;
function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.dart')) {
      let m;
      const c = fs.readFileSync(p, 'utf8');
      while ((m = re.exec(c))) used.add(m[1]);
    }
  }
}
walk(path.join(__dirname, '..', 'lib'));

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
for (const lang of ['ar', 'fr', 'es', 'tr', 'ur', 'hi', 'bn', 'ru', 'zh']) {
  const m = parseLang(lang);
  const same = [...used]
    .filter((k) => m[k] && en[k] && m[k] === en[k])
    .sort();
  console.log(`\n${lang.toUpperCase()} (${same.length} keys still in English):`);
  for (const k of same) console.log(`  ${k} = "${en[k]}"`);
}
