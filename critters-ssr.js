/**
 * critters-ssr.js
 *
 * REMEDIATION: cz-css-1008 – Critical CSS Not Extracted for Container SSR
 *
 * This script is executed during the Docker css-builder stage to inline
 * critical above-fold CSS from critical-unextracted.css into SSR HTML
 * templates served from EKS pods.
 *
 * HOW IT WORKS
 * ------------
 * 1. Critters reads each HTML file in the SSR output directory.
 * 2. It identifies which CSS rules from the linked stylesheets (including
 *    critical-unextracted.css) are required to render above-the-fold content.
 * 3. Those critical rules are inlined as a <style> block in the HTML <head>.
 * 4. The original <link rel="stylesheet"> tags are converted to
 *    <link rel="preload"> so non-critical CSS loads asynchronously without
 *    blocking the initial render.
 *
 * USAGE (Dockerfile css-builder stage)
 * -------------------------------------
 *   node critters-ssr.js
 *
 * Environment variables:
 *   SSR_HTML_DIR   – directory containing SSR HTML files to process
 *                    (default: ./dist/html)
 *   CSS_PUBLIC_PATH – public URL path prefix for stylesheet hrefs
 *                    (default: /assets/styles)
 */

'use strict';

const Critters = require('critters');
const fs       = require('fs');
const path     = require('path');
const glob     = require('glob');

const SSR_HTML_DIR    = process.env.SSR_HTML_DIR    || './dist/html';
const CSS_PUBLIC_PATH = process.env.CSS_PUBLIC_PATH || '/assets/styles';

// Resolve the directory that contains the processed (purged + minified) CSS files.
// The Dockerfile copies them to dist/styles after the PostCSS pipeline runs.
const CSS_OUTPUT_DIR = path.resolve('./dist/styles');

async function extractCriticalCSS() {
  // Initialise Critters with the path to the processed CSS assets.
  const critters = new Critters({
    // Path on disk where Critters can read the CSS files referenced by <link> tags.
    path: CSS_OUTPUT_DIR,
    // Public URL prefix used in <link href="..."> attributes inside the HTML.
    publicPath: CSS_PUBLIC_PATH,
    // Inline critical CSS as a <style> block and convert <link> to preload.
    preload: 'swap',
    // Remove the inlined rules from the external stylesheet to avoid duplication.
    pruneSource: false,
    // Reduce inlined CSS size by merging identical media queries.
    mergeStylesheets: true,
    // Compress the inlined <style> block.
    compress: true,
    // Log level: 'info' | 'warn' | 'error' | 'silent'
    logLevel: 'warn',
  });

  // Discover all HTML files in the SSR output directory.
  const htmlDir = path.resolve(SSR_HTML_DIR);
  if (!fs.existsSync(htmlDir)) {
    console.warn(
      `[critters-ssr] SSR_HTML_DIR "${htmlDir}" does not exist – ` +
      'skipping critical CSS extraction. ' +
      'Set SSR_HTML_DIR to the directory containing your SSR HTML output.'
    );
    return;
  }

  const htmlFiles = glob.sync('**/*.html', { cwd: htmlDir, absolute: true });

  if (htmlFiles.length === 0) {
    console.warn(
      `[critters-ssr] No HTML files found in "${htmlDir}". ` +
      'Critical CSS extraction skipped.'
    );
    return;
  }

  let processed = 0;
  let failed    = 0;

  for (const htmlFile of htmlFiles) {
    try {
      const originalHtml = fs.readFileSync(htmlFile, 'utf8');
      const inlinedHtml  = await critters.process(originalHtml);
      fs.writeFileSync(htmlFile, inlinedHtml, 'utf8');
      console.log(`[critters-ssr] ✔ Inlined critical CSS → ${path.relative(htmlDir, htmlFile)}`);
      processed++;
    } catch (err) {
      console.error(`[critters-ssr] ✘ Failed to process ${htmlFile}: ${err.message}`);
      failed++;
    }
  }

  console.log(
    `[critters-ssr] Done. Processed: ${processed}, Failed: ${failed}, ` +
    `Total: ${htmlFiles.length}`
  );

  if (failed > 0) {
    process.exit(1);
  }
}

extractCriticalCSS().catch((err) => {
  console.error('[critters-ssr] Unexpected error:', err);
  process.exit(1);
});
