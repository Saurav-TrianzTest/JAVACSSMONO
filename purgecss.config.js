/**
 * PurgeCSS Configuration
 * ============================================================================
 * Rule: cz-css-1005 — Unused CSS in Container Images
 *
 * Strategy: AWS CodeBuild CI Pipeline with PurgeCSS Step
 * This configuration is consumed by the PurgeCSS step in buildspec.yml.
 * PurgeCSS scans all HTML, JS, and JSX/TSX content files to determine which
 * CSS selectors are actually used, then strips unused rules from every CSS
 * file under assets/styles/ before the Docker image is built and pushed to
 * Amazon ECR. This ensures every ECS Fargate task revision uses a
 * CSS-optimised image without manual intervention.
 *
 * Benefit: Reduces container image size, lowers ECR registry storage costs,
 * and speeds up ECS Fargate cold-start times and Kubernetes deployments.
 * ============================================================================
 */

module.exports = {
  /**
   * Content sources — PurgeCSS scans these files to detect used CSS selectors.
   * Extend this list if additional template or component directories are added.
   */
  content: [
    // Java/Spring Boot server-side templates (Thymeleaf, Freemarker, JSP, etc.)
    'src/main/resources/templates/**/*.html',
    'src/main/resources/static/**/*.html',
    'src/main/webapp/**/*.html',
    'src/main/webapp/**/*.jsp',

    // Frontend JavaScript / component files
    'frontend/**/*.js',
    'frontend/**/*.jsx',
    'frontend/**/*.ts',
    'frontend/**/*.tsx',

    // Any top-level HTML entry points
    '*.html',
    'public/**/*.html',
  ],

  /**
   * CSS files to process — PurgeCSS reads these and removes unused selectors.
   * The output (purged) files overwrite the originals in-place so the
   * subsequent Docker COPY step picks up the optimised versions.
   */
  css: [
    'assets/styles/**/*.css',
  ],

  /**
   * Safelist — selectors that must NEVER be removed even if not found in
   * content scans (e.g. dynamically injected classes, third-party widget
   * selectors, or classes added via JavaScript at runtime).
   */
  safelist: {
    // Exact selectors to always keep
    standard: [
      // Spring Boot Actuator / health endpoint styles (if any)
      /^actuator/,
      // Bootstrap utility classes that may be injected dynamically
      /^(d-|p-|m-|text-|bg-|border-|flex-|align-|justify-)/,
    ],
    // Deep safelist: keep selectors matching these patterns regardless of depth
    deep: [
      /active$/,
      /open$/,
      /show$/,
      /hidden$/,
      /visible$/,
      /disabled$/,
    ],
    // Greedy safelist: keep any selector containing these substrings
    greedy: [],
  },

  /**
   * Rejected CSS — write a separate file listing all removed selectors for
   * audit purposes. The CodeBuild step uploads this artefact to S3.
   */
  rejected: true,
  rejectedCss: true,

  /**
   * Variables — preserve CSS custom properties (--var-name) even if not
   * referenced in scanned content, as they may be used in inline styles.
   */
  variables: true,

  /**
   * Font-face — always keep @font-face rules to avoid broken typography.
   */
  fontFace: true,

  /**
   * Keyframes — keep @keyframes referenced by kept animation properties.
   */
  keyframes: true,
};
