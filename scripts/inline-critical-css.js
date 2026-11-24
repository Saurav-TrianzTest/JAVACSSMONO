// cz-css-1008: Extract critical (above-fold) CSS with Critters and inline it into
// the <head> of every HTML document so SSR pods in EKS avoid render-blocking
// stylesheet loads.
const fs = require('fs');
const path = require('path');
const Critters = require('critters');

const root = process.env.HTML_ROOT || process.cwd();
const critters = new Critters({
  path: root,
  publicPath: '/',
  preload: 'swap',
  pruneSource: false,
  inlineFonts: false,
  logLevel: 'info'
});

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.git') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.html')) out.push(full);
  }
  return out;
}

(async () => {
  const files = walk(root, []);
  for (const file of files) {
    const html = fs.readFileSync(file, 'utf8');
    const inlined = await critters.process(html);
    fs.writeFileSync(file, inlined);
    console.log('Inlined critical CSS into ' + file);
  }
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
