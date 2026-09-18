/**
 * PurgeCSS configuration for the Docker multi-stage build (css-builder stage).
 *
 * PurgeCSS scans the content sources listed below to determine which CSS
 * selectors are actually used.  Any selector NOT found in these sources is
 * removed from the output CSS, eliminating dead rules such as
 * .ghost-widget-deprecated (old-theme.css, line 21) that bloat container
 * images and increase EKS deployment time.
 *
 * Rule: cz-css-1005 – Unused CSS in Container Images
 * Remediation: Integrate PurgeCSS in Multi-Stage Dockerfile for EKS Deployments
 */
module.exports = {
  // Content sources PurgeCSS will scan for used CSS class/id/element selectors.
  // Add or adjust glob patterns to match all HTML, JS, JSX, TS, TSX, and
  // server-side template files that reference CSS classes in this project.
  content: [
    './frontend/**/*.{js,jsx,ts,tsx,html}',
    './src/main/resources/templates/**/*.{html,ftl,vm,jsp}',
    './src/main/resources/static/**/*.{html,js}'
  ],

  // CSS variables and dynamically constructed class names that PurgeCSS
  // cannot detect statically should be listed here to prevent false removal.
  safelist: {
    // Preserve standard structural / utility selectors
    standard: [
      'html',
      'body',
      ':root',
      /^btn/,
      /^card/,
      /^hero/,
      /^banner/,
      /^splash/,
      /^icon-/
    ],
    // Preserve CSS custom-property declarations (--variable: value)
    deep: [/^--/],
    // Preserve @keyframes referenced by kept rules
    greedy: [/^animate-/]
  },

  // Treat CSS variables (var(--x)) as used so :root declarations are kept
  variables: true,

  // Reject @font-face blocks whose font-family is not referenced in kept rules
  fontFace: true
};
