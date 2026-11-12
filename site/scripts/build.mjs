import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { transform } from 'esbuild';
import { compile } from 'tailwindcss';
import { Scanner } from '@tailwindcss/oxide';
import { createRequire } from 'node:module';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceFiles = [
  'src/types.ts',
  'src/00-config-runtime.ts',
  'src/04-antiscrape.ts',
  'src/templates/01-design-shell.ts',
  'src/templates/02-home.ts',
  'src/templates/03-player.ts',
  'src/templates/04-status.ts',
  'src/05-settings-admin.ts',
  'src/05a-admin-users.ts',
  'src/05b-social.ts',
  'src/05c-members.ts',
  'src/05e-api-v1.ts',
  'src/05d-checkhost.ts',
  'src/templates/05-checkhost.ts',
  'src/06a-seo.ts',
  'src/06-telegram.ts',
  'src/07-router.ts',
];

const sections = await Promise.all(sourceFiles.map(async (file) => {
  const source = await readFile(resolve(projectRoot, file), 'utf8');
  return `\n/* ── ${file} ───────────────────────────────────────────────── */\n${source}`;
}));
async function assetSection() {
  const out = {};
  for (const dir of ['providers', 'brand', 'fonts', 'icons', 'flags', 'logos']) {
    let files = [];
    try { files = await readdir(resolve(projectRoot, 'assets', dir)); } catch (_) {}
    for (const f of files.sort()) {
      if (!/\.(png|svg|ttf|otf|woff|woff2)$/i.test(f)) continue;
      const buf = await readFile(resolve(projectRoot, 'assets', dir, f));
      const mime = /\.svg$/i.test(f) ? 'image/svg+xml' : /\.png$/i.test(f) ? 'image/png' : /\.woff2$/i.test(f) ? 'font/woff2' : /\.woff$/i.test(f) ? 'font/woff' : /\.otf$/i.test(f) ? 'font/otf' : 'font/ttf';
      out['/assets/' + dir + '/' + f] = [mime, buf.toString('base64')];
    }
  }
  // Social/bot icons: inline SVG markup (title removed, currentColor) for the templates.
  const icons = {};
  let iconFiles = [];
  try { iconFiles = await readdir(resolve(projectRoot, 'assets', 'icons')); } catch (_) {}
  for (const f of iconFiles.sort()) {
    if (!/\.svg$/i.test(f)) continue;
    let svg = (await readFile(resolve(projectRoot, 'assets', 'icons', f), 'utf8')).trim();
    svg = svg.replace(/<title>[\s\S]*?<\/title>/g, '').replace(/\s(role|xmlns)="[^"]*"/g, '').replace(/\s+/g, ' ');
    if (!/^<svg[^>]*\s(fill|stroke)=/.test(svg)) svg = svg.replace(/^<svg/, '<svg fill="currentColor"');
    icons[f.replace(/\.svg$/i, '').toLowerCase()] = svg.replace(/^<svg/, '<svg aria-hidden="true" focusable="false"');
  }
  return '\n/* ── assets/ (embedded at build time) ── */\nconst STATIC_ASSETS: Record<string, [string, string]> = ' + JSON.stringify(out) + ';\n' +
    'const SOCIAL_ICON_FILES: Record<string, string> = ' + JSON.stringify(icons) + ';\n';
}
sections.unshift(await assetSection());
// Tailwind CSS: src/styles/app.css is the only stylesheet. It is compiled here
// (utilities found in every src/**/*.ts template) and embedded as APP_CSS.
async function tailwindSection() {
  const require = createRequire(import.meta.url);
  const twDir = dirname(require.resolve('tailwindcss/package.json'));
  const entry = resolve(projectRoot, 'src/styles/app.css');
  const input = await readFile(entry, 'utf8');
  const compiler = await compile(input, {
    base: dirname(entry),
    loadStylesheet: async (id, base) => {
      const file = id === 'tailwindcss' ? resolve(twDir, 'index.css') : id.startsWith('tailwindcss/') ? resolve(twDir, id.slice('tailwindcss/'.length)) : resolve(base, id);
      return { path: file, base: dirname(file), content: await readFile(file, 'utf8') };
    },
  });
  const scanner = new Scanner({ sources: [{ base: resolve(projectRoot, 'src'), pattern: '**/*.ts', negated: false }] });
  let css = compiler.build(scanner.scan());
  const min = await transform(css, { loader: 'css', minify: true });
  css = min.code.trim();
  await writeFile(resolve(projectRoot, 'dist/app.css'), css);
  return '\n/* ── src/styles/app.css (Tailwind CSS, compiled at build time) ── */\nconst APP_CSS: string = ' + JSON.stringify(css) + ';\n';
}
await mkdir(resolve(projectRoot, 'dist'), { recursive: true });
sections.unshift(await tailwindSection());

const combined = sections.join('\n');
const typecheckSource = resolve(projectRoot, '.build/worker.ts');
await mkdir(dirname(typecheckSource), { recursive: true });
await writeFile(typecheckSource, combined);
const result = await transform(combined, {
  loader: 'ts',
  target: 'es2022',
  format: 'esm',
  legalComments: 'none',
  sourcemap: true,
  sourcefile: 'src/worker.ts',
});
const output = resolve(projectRoot, 'dist/worker.js');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, result.code);
await writeFile(`${output}.map`, result.map);
console.log(`Built ${sourceFiles.length} source sections → dist/worker.js`);
