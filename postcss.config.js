// postcss.config.js — CSS minification pipeline for production container builds.
// Used in the css-build stage of the multi-stage Dockerfile to strip whitespace,
// comments, and redundant declarations before copying assets into the final image.
// PurgeCSS (cz-css-1005) runs as a separate pre-step via purgecss.config.js
// before PostCSS minification so that unused rules are removed first.
module.exports = {
  plugins: [
    require('cssnano')({
      preset: [
        'default',
        {
          discardComments: { removeAll: true },
          normalizeWhitespace: true,
          minifySelectors: true,
          minifyParams: true,
          reduceIdents: false,
          mergeRules: false
        }
      ]
    })
  ]
};
