const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const translationsPath = path.join(root, 'lib', 'lang', 'translations.dart');
const corePath = path.join(__dirname, 'core_ui_translations.json');

let src = fs.readFileSync(translationsPath, 'utf8');
const core = JSON.parse(fs.readFileSync(corePath, 'utf8'));

function escapeDart(str) {
  return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function parseLangBlock(lang, text) {
  const blockRe = new RegExp(`'${lang}':\\s*\\{([\\s\\S]*?)\\n  \\},`);
  const match = text.match(blockRe);
  if (!match) return { keys: {}, raw: '', full: null };
  const keys = {};
  const lineRe = /'([a-z][a-z0-9_]*)':\s*'((?:\\'|[^'])*)'/g;
  let m;
  while ((m = lineRe.exec(match[1]))) keys[m[1]] = m[2];
  return { keys, raw: match[1], full: match[0] };
}

function replaceKeyInBlock(body, key, value) {
  const escaped = escapeDart(value);
  const multiRe = new RegExp(`'${key}':\\s*\\n\\s*'(?:\\\\'|[^'])*',`);
  if (multiRe.test(body)) {
    return {
      body: body.replace(multiRe, `'${key}':\n        '${escaped}',`),
      replaced: true,
    };
  }
  const singleRe = new RegExp(`'${key}':\\s*'(?:\\\\'|[^'])*',`);
  if (singleRe.test(body)) {
    return {
      body: body.replace(singleRe, `'${key}': '${escaped}',`),
      replaced: true,
    };
  }
  return { body, replaced: false };
}

const counts = {};

for (const lang of Object.keys(core)) {
  const blockRe = new RegExp(`('${lang}':\\s*\\{)([\\s\\S]*?)(\\n  \\},)`);
  const match = src.match(blockRe);
  if (!match) {
    console.log(`Patched ${lang}: block not found`);
    counts[lang] = 0;
    continue;
  }

  let body = match[2];
  let patched = 0;
  let missing = 0;

  for (const [key, value] of Object.entries(core[lang])) {
    const result = replaceKeyInBlock(body, key, value);
    body = result.body;
    if (result.replaced) patched++;
    else missing++;
  }

  src = src.replace(blockRe, `${match[1]}${body}${match[3]}`);
  counts[lang] = patched;
  console.log(`Patched ${lang}: ${patched} keys${missing ? ` (${missing} not found)` : ''}`);
}

fs.writeFileSync(translationsPath, src, 'utf8');
console.log('Done.');
