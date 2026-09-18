// postcss.config.js – used by the css-builder stage in the multi-stage Dockerfile
//
// Plugin pipeline (executed in order):
//
// 1. @fullhuman/postcss-purgecss  – strips unused CSS rules (cz-css-1005 fix)
//    Content paths are the JS/HTML sources that PurgeCSS scans for used selectors.
//
// 2. cssnano                      – minifies the purged output for minimal image size.
//
// NOTE: Critical CSS extraction (cz-css-1008) is handled by the Critters step that
//       runs AFTER PostCSS in the Dockerfile css-builder stage.  Critters reads the
//       built HTML files, inlines the rules marked with /* critters:include */ from
//       assets/styles/critical-unextracted.css, and converts the full stylesheet
//       <link> to a non-blocking preload so that AKS SSR pods achieve fast FCP.
module.exports = {
  plugins: [
    require('@fullhuman/postcss-purgecss')({
      content: [
        './frontend/**/*.js',
        './frontend/**/*.jsx',
        './frontend/**/*.ts',
        './frontend/**/*.tsx',
        './src/main/resources/templates/**/*.html',
        './src/main/resources/static/**/*.html'
      ],
      defaultExtractor: content => content.match(/[\w-/:]+(?<!:)/g) || [],
      safelist: {
        // Preserve any selector that is still referenced at runtime
        standard: [],
        deep: [],
        greedy: []
      }
    }),
    require('cssnano')({
      preset: ['default', {
        discardComments: { removeAll: true },
        normalizeWhitespace: true,
        minifySelectors: true,
        minifyFontValues: true,
        reduceIdents: false
      }]
    })
  ]
};
