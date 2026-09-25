/**
 * PurgeCSS Configuration
 *
 * cz-css-1005: Unused CSS in Container Images
 * Remediation: AWS CodeBuild CI Pipeline with PurgeCSS Step for Automated ECS Fargate Image Optimization
 *
 * This configuration is consumed by the PurgeCSS step in buildspec.yml.
 * PurgeCSS scans all content files listed below and removes any CSS selectors
 * (including .ghost-widget-deprecated and other dead rules) that are not
 * referenced in the active codebase, producing a minimal CSS bundle for the
 * production ECS Fargate container image pushed to ECR.
 *
 * Benefits:
 *   - Reduces container image size stored in ECR
 *   - Accelerates ECS Fargate task startup and Kubernetes deployments
 *   - Eliminates CSS rules for removed components (e.g. .ghost-widget-deprecated)
 */
module.exports = {
  // Content files PurgeCSS will scan for used CSS selectors
  content: [
    './src/**/*.html',
    './src/**/*.java',
    './src/**/*.jsp',
    './frontend/**/*.js',
    './frontend/**/*.jsx',
    './frontend/**/*.ts',
    './frontend/**/*.tsx',
    './frontend/**/*.html',
    './templates/**/*.html',
    './public/**/*.html',
    '*.html',
  ],

  // CSS files to process and purge
  css: [
    './assets/styles/old-theme.css',
    './assets/styles/main.scss.css',
    './assets/styles/base.css',
    './assets/styles/app.min.css',
    './assets/styles/styles.dev.css',
  ],

  // Output directory for purged CSS files
  output: './assets/styles/purged/',

  // Safelist: selectors that must never be removed even if not found in content scans.
  // Add selectors here that are injected dynamically at runtime.
  safelist: {
    standard: [],
    deep: [],
    greedy: [],
  },

  // Blocklist: selectors that must always be removed regardless of content scan results.
  // .ghost-widget-deprecated is a removed component and must be stripped from production CSS.
  blocklist: [
    '.ghost-widget-deprecated',
  ],

  // Reject: reject CSS files that do not match the content patterns
  rejected: false,

  // Print rejected selectors to stdout for audit logging in CodeBuild
  rejectedCss: false,

  // Variables: remove unused CSS custom properties
  variables: false,

  // Font face: remove unused @font-face rules
  fontFace: false,

  // Keyframes: remove unused @keyframes rules
  keyframes: false,
};
