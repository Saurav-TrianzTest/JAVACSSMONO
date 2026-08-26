// purgecss.config.js — PurgeCSS configuration for cz-css-1005 remediation.
// Removes unused CSS rules (e.g. .ghost-widget-deprecated and other orphaned
// selectors for removed components) before the final production image is built.
// This keeps the container image lean for EKS deployments.
module.exports = {
  // Source files PurgeCSS scans to determine which selectors are actually used.
  content: [
    'src/**/*.java',
    'src/**/*.html',
    'frontend/**/*.js',
    'frontend/**/*.jsx',
    'frontend/**/*.ts',
    'frontend/**/*.tsx'
  ],

  // CSS files to purge.
  css: [
    'assets/styles/old-theme.css',
    'assets/styles/base.css',
    'assets/styles/styles.dev.css',
    'assets/styles/critical-unextracted.css',
    'assets/styles/main.scss.css'
  ],

  // Output directory for purged CSS files (overwrite in-place for the build stage).
  output: 'assets/styles/',

  // Safelist: selectors that must never be removed even if not found in content
  // files (e.g. dynamically injected classes, third-party widget classes).
  safelist: {
    standard: [
      /^hero$/,
      /^banner$/,
      /^splash$/,
      /^icon-/
    ],
    // Explicitly block deprecated/removed-component selectors so PurgeCSS
    // strips them even if they somehow appear in a comment or string literal.
    blocklist: [
      /ghost-widget-deprecated/
    ]
  },

  // Preserve @font-face, @keyframes, and CSS variables used at runtime.
  variables: true,
  keyframes: true,
  fontFace: true
};
