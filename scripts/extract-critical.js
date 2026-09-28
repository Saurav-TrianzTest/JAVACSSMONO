/**
 * extract-critical.js
 * cz-css-1008 remediation: Critters-based critical CSS extraction script
 *
 * Integrates Critters into the CI/CD build pipeline to inline critical
 * above-fold CSS into SSR-rendered HTML pages served from AKS pods.
 *
 * This script:
 *   1. Reads SSR-rendered HTML files from dist/ssr/
 *   2. Runs Critters to identify and inline critical above-fold CSS rules
 *      (including those defined in assets/styles/critical-unextracted.css)
 *   3. Converts non-critical stylesheet <link> tags to async preload
 *   4. Writes the optimised HTML to dist/ssr-critical/
 *
 * The resulting HTML is deployed to AKS via Azure Container Registry (ACR)
 * using Workload Identity for secure image pulls, ensuring fast First
 * Contentful Paint (FCP) from Kubernetes SSR pods without render-blocking
 * external CSS requests.
 *
 * Usage (CI/CD step after SSR build):
 *   npm run extract:critical
 *
 * Environment variables:
 *   SSR_INPUT_DIR   - Directory containing SSR-rendered HTML (default: dist/ssr)
 *   SSR_OUTPUT_DIR  - Directory for Critters-processed HTML (default: dist/ssr-critical)
 */

'use strict';

const Critters = require('critters');
const fs       = require('fs');
const path     = require('path');

const SSR_INPUT_DIR  = process.env.SSR_INPUT_DIR  || path.join(__dirname, '..', 'dist', 'ssr');
const SSR_OUTPUT_DIR = process.env.SSR_OUTPUT_DIR || path.join(__dirname, '..', 'dist', 'ssr-critical');

// Ensure output directory exists
fs.mkdirSync(SSR_OUTPUT_DIR, { recursive: true });

// Initialise Critters with AKS SSR-optimised settings
const critters = new Critters({
  // Path where the built CSS assets reside (copied from css-builder stage)
  path: path.join(__dirname, '..', 'dist', 'styles'),

  // Public URL prefix used in <link href="..."> tags within the SSR HTML
  publicPath: '/assets/styles/',

  // Inline critical CSS as a <style> block in <head>
  inlineFonts: false,

  // Convert non-critical <link rel="stylesheet"> to async preload pattern:
  //   <link rel="preload" as="style" onload="this.rel='stylesheet'">
  preload: 'swap',

  // Remove the original blocking <link> after inlining critical rules
  pruneSource: false,

  // Reduce inlined CSS to only the rules actually used above the fold
  reduceInlineStyles: true,

  // Log progress to stdout for CI/CD visibility
  logger: {
    info:  (msg) => console.log(`[critters:info]  ${msg}`),
    warn:  (msg) => console.warn(`[critters:warn]  ${msg}`),
    error: (msg) => console.error(`[critters:error] ${msg}`)
  }
});

/**
 * Process all HTML files in the SSR input directory.
 */
async function run() {
  if (!fs.existsSync(SSR_INPUT_DIR)) {
    console.warn(
      `[extract-critical] SSR input directory not found: ${SSR_INPUT_DIR}\n` +
      `  Skipping critical CSS extraction (no SSR HTML to process).`
    );
    process.exit(0);
  }

  const htmlFiles = fs
    .readdirSync(SSR_INPUT_DIR)
    .filter((f) => f.endsWith('.html'));

  if (htmlFiles.length === 0) {
    console.warn(`[extract-critical] No HTML files found in ${SSR_INPUT_DIR}`);
    process.exit(0);
  }

  let processed = 0;
  let failed    = 0;

  for (const file of htmlFiles) {
    const inputPath  = path.join(SSR_INPUT_DIR, file);
    const outputPath = path.join(SSR_OUTPUT_DIR, file);

    try {
      const html         = fs.readFileSync(inputPath, 'utf8');
      const criticalHtml = await critters.process(html);
      fs.writeFileSync(outputPath, criticalHtml, 'utf8');
      console.log(`[extract-critical] ✔  ${file}`);
      processed++;
    } catch (err) {
      console.error(`[extract-critical] ✘  ${file}: ${err.message}`);
      failed++;
    }
  }

  console.log(
    `\n[extract-critical] Done — ${processed} processed, ${failed} failed.`
  );

  if (failed > 0) {
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('[extract-critical] Fatal error:', err);
  process.exit(1);
});
