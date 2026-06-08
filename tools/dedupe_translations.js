const fs = require('fs');
const path = require('path');

const translationsPath = path.join(__dirname, '..', 'lib', 'lang', 'translations.dart');
let src = fs.readFileSync(translationsPath, 'utf8');

const langs = ['en', 'ar', 'fr', 'es', 'tr', 'ur', 'hi', 'bn', 'ru', 'zh'];

const legalTitles = {
  en: 'Legal Documents',
  ar: 'الوثائق القانونية',
  fr: 'Documents juridiques',
  es: 'Documentos legales',
  tr: 'Yasal belgeler',
  ur: 'قانونی دستاویزات',
  hi: 'कानूनी दस्तावेज़',
  bn: 'আইনি নথিপত্র',
  ru: 'Юридические документы',
  zh: '法律文件',
};

function escapeDart(str) {
  return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

for (const lang of langs) {
  const blockRe = new RegExp(`('${lang}':\\s*\\{)([\\s\\S]*?)(\\n  \\},)`);
  const match = src.match(blockRe);
  if (!match) continue;

  const lines = match[2].split('\n');
  const seen = new Set();
  const kept = [];
  let removed = 0;

  for (const line of lines) {
    const keyMatch = line.match(/^\s*'([a-z][a-z0-9_]*)':/);
    if (keyMatch) {
      const key = keyMatch[1];
      if (seen.has(key)) {
        removed++;
        continue;
      }
      seen.add(key);
      if (key === 'legal_documents_title') {
        kept.push(`    'legal_documents_title': '${escapeDart(legalTitles[lang])}',`);
        continue;
      }
    }
    kept.push(line);
  }

  if (removed > 0 || match[2].includes("'legal_documents_title': 'legal_documents_title'")) {
    src = src.replace(blockRe, `${match[1]}${kept.join('\n')}${match[3]}`);
    console.log(`${lang}: removed ${removed} duplicate keys`);
  }
}

fs.writeFileSync(translationsPath, src, 'utf8');
console.log('Done deduping.');
