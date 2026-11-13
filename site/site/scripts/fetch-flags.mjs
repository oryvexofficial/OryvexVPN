// Re-download the flags + logos from the internet. Run: npm run flags && npm run deploy
import { writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'assets');
const files = [
  ...['ir', 'us', 'de', 'gb', 'fr', 'nl'].map(cc => ['flags/' + cc + '.svg', 'https://raw.githubusercontent.com/hampusborgos/country-flags/main/svg/' + cc + '.svg']),
  ['logos/cloudflare.svg', 'https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/cloudflare.svg', s => s.replace('<svg ', '<svg fill="#F38020" ')]
];
for (const [out, url, fix] of files) {
  const r = await fetch(url);
  if (!r.ok) { console.error('skip ' + out + ' (' + r.status + ')'); continue; }
  let svg = await r.text();
  if (fix) svg = fix(svg);
  await writeFile(resolve(root, out), svg);
  console.log('saved assets/' + out);
}
