// critters.config.js — Critical CSS extraction for cz-css-1008 remediation.
//
// Critters scans every HTML file produced by the SSR build, identifies the
// above-fold (critical) CSS rules referenced by those pages, inlines them
// into a <style> block inside <head>, and converts the original
// <link rel="stylesheet"> to load asynchronously so it no longer blocks
// rendering in EKS SSR pods.
//
// Run via:  node critters.config.js
// (invoked as `npm run extract:critical` in the css-build Docker stage)

'use strict';

const path = require('path');
const fs   = require('fs');
const Critters = require('critters');

// ── Configuration ────────────────────────────────────────────────────────────

// Directory that contains the SSR-rendered HTML files to process.
// In the Docker css-build stage this is the output of the SSR render step.
const HTML_DIR = process.env.SSR_HTML_DIR || path.resolve(__dirname, 'src/main/resources/templates');

// Directory where the minified/purged CSS assets live (produced by build:css).
const CSS_PUBLIC_PATH = process.env.CSS_PUBLIC_PATH || '/assets/styles/';

// ── Critters instance ────────────────────────────────────────────────────────

const critters = new Critters({
  // Path to the directory that Critters treats as the web root when resolving
  // stylesheet hrefs found in the HTML files.
  path: path.resolve(__dirname),

  // Public URL prefix used in <link href="..."> tags inside the HTML.
  publicPath: CSS_PUBLIC_PATH,

  // Inline critical CSS as a <style> block and make the original stylesheet
  // load asynchronously (rel="preload" + onload swap) to eliminate
  // render-blocking requests from EKS SSR pods.
  preload: 'swap',

  // Remove the <link> tag for stylesheets that are fully inlined (i.e. when
  // the entire stylesheet fits within the critical budget).
  pruneSource: false,

  // Reduce inlined <style> size by merging identical media queries.
  mergeStylesheets: true,

  // Emit a console warning when a referenced stylesheet cannot be found so
  // CI/CD pipelines can catch misconfigured asset paths early.
  logLevel: 'warn',

  // Additional selectors that must always be treated as critical even if
  // Critters' static analysis does not detect them in the above-fold HTML
  // (e.g. dynamically injected classes, JS-driven animations).
  additionalStylesheets: [],
});

// ── Process HTML files ───────────────────────────────────────────────────────

(async () => {
  // Collect all .html files under HTML_DIR (recursive).
  function collectHtml(dir) {
    if (!fs.existsSync(dir)) {
      console.warn(`[critters] HTML directory not found: ${dir} — skipping.`);
      return [];
    }
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    return entries.flatMap(entry => {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) return collectHtml(full);
      if (entry.isFile() && entry.name.endsWith('.html')) return [full];
      return [];
    });
  }

  const htmlFiles = collectHtml(HTML_DIR);

  if (htmlFiles.length === 0) {
    console.log('[critters] No HTML files found — nothing to process.');
    process.exit(0);
  }

  let processed = 0;
  let failed    = 0;

  for (const filePath of htmlFiles) {
    try {
      const original = fs.readFileSync(filePath, 'utf8');
      const inlined  = await critters.process(original);
      fs.writeFileSync(filePath, inlined, 'utf8');
      console.log(`[critters] ✔ Inlined critical CSS → ${path.relative(__dirname, filePath)}`);
      processed++;
    } catch (err) {
      console.error(`[critters] ✘ Failed to process ${filePath}: ${err.message}`);
      failed++;
    }
  }

  console.log(`\n[critters] Done. Processed: ${processed}, Failed: ${failed}`);
  if (failed > 0) process.exit(1);
})();
