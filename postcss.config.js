// postcss.config.js
// PostCSS configuration for CSS optimization pipeline (cz-css-1004 + cz-css-1005)
// Used in the multi-stage Dockerfile CSS builder stage to:
//   1. Remove unused CSS rules via PurgeCSS (cz-css-1005) - eliminates dead
//      selectors like .ghost-widget-deprecated left from removed components.
//   2. Minify the purged output via cssnano (cz-css-1004) - reduces ACR
//      storage costs and AKS pod startup time.

module.exports = {
  plugins: [
    // cz-css-1005: PurgeCSS - remove unused CSS rules by scanning frontend sources
    require('@fullhuman/postcss-purgecss')({
      // Scan all JS component files for used CSS selectors
      content: ['./frontend/**/*.js'],
      // Default extractor handles standard class/id selectors
      defaultExtractor: content => content.match(/[\w-/:]+(?<!:)/g) || [],
      // Safelist patterns to preserve dynamic/utility classes
      safelist: {
        standard: [],
        deep: [],
        greedy: []
      }
    }),
    // cz-css-1004: cssnano - minify the purged CSS output
    require('cssnano')({
      preset: [
        'default',
        {
          // Remove all comments (whitespace, inline comments, block comments)
          discardComments: { removeAll: true },
          // Normalize whitespace
          normalizeWhitespace: true,
          // Merge duplicate rules
          mergeLonghand: true,
          // Remove duplicate rules
          discardDuplicates: true,
          // Minify selectors
          minifySelectors: true,
          // Minify font values
          minifyFontValues: true,
          // Minify gradients
          minifyGradients: true,
          // Reduce initial values
          reduceInitial: true,
          // Reduce transforms
          reduceTransforms: true,
          // Normalize unicode
          normalizeUnicode: true,
          // Minify params
          minifyParams: true,
          // Normalize string
          normalizeString: true,
          // Normalize timing functions
          normalizeTimingFunctions: true,
          // Normalize positions
          normalizePositions: true,
          // Normalize repeat style
          normalizeRepeatStyle: true,
          // Normalize border
          normalizeBorder: true,
          // Normalize display values
          normalizeDisplayValues: true,
          // Normalize overflow shorthand
          normalizeOverflowShorthand: true,
          // Orderly values
          orderedValues: true,
          // Unique selectors
          uniqueSelectors: true,
          // Convert values
          convertValues: true,
          // Calc optimization
          calc: true,
          // Color minimization
          colormin: true,
          // Z-index rebasing disabled (unsafe for multi-file projects)
          zindex: false,
          // CSS custom properties - keep for runtime theming
          cssDeclarationSorter: false
        }
      ]
    })
  ]
};
