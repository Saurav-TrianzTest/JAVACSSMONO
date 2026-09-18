// PostCSS configuration for the Docker multi-stage CSS optimization pipeline.
//
// Pipeline order:
//   1. @fullhuman/postcss-purgecss  – removes unused CSS rules (e.g. .ghost-widget-deprecated)
//      by scanning the content sources listed in purgecss.config.js.
//   2. cssnano                      – minifies the purged CSS for minimal production image size.
//
// CRITICAL CSS EXTRACTION (cz-css-1008 remediation)
//   Critters is integrated into the SSR HTML generation step (see Dockerfile critters-ssr stage).
//   It scans SSR HTML output and inlines above-fold rules from critical-unextracted.css directly
//   into the <head> of each HTML response served from EKS pods, eliminating render-blocking
//   stylesheet loads and improving First Contentful Paint (FCP).
//
// This configuration is used exclusively in the css-builder Docker stage and
// reduces ECR storage costs and EKS pod startup time for containerized deployments.
const purgeCSSPlugin = require('@fullhuman/postcss-purgecss');
const cssnano        = require('cssnano');
const purgeCSSConfig = require('./purgecss.config.js');

module.exports = {
  plugins: [
    // Step 1: Strip unused CSS selectors (cz-css-1005 remediation)
    purgeCSSPlugin(purgeCSSConfig),

    // Step 2: Minify the purged CSS
    cssnano({
      preset: ['default', {
        discardComments: { removeAll: true },
        normalizeWhitespace: true,
        minifySelectors: true,
        minifyParams: true,
        reduceIdents: false
      }]
    })
  ]
};
