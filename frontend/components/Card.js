/**
 * SSR Style Extraction – cz-css-1007
 *
 * @emotion/server is used to extract critical CSS on the server so that styles
 * are inlined into the HTML response before the EKS pod serves the page.
 * This eliminates Flash of Unstyled Content (FOUC) in SSR / Kubernetes workloads.
 *
 * Usage in your SSR entry-point (e.g. pages/_document.js for Next.js):
 *
 *   import { extractCritical } from '@emotion/server';
 *   import { renderToString } from 'react-dom/server';
 *   import { cache } from './emotionCache';          // shared Emotion cache
 *
 *   const html   = renderToString(<App />);
 *   const { css, ids } = extractCritical(html);
 *   // Inject <style data-emotion={ids.join(' ')}>{css}</style> into <head>
 *
 * Required package (add to package.json):
 *   "@emotion/server": "^11.11.0"
 */

import styled from '@emotion/styled';
import createCache from '@emotion/cache';
import { extractCritical } from '@emotion/server';

/**
 * Shared Emotion cache instance.
 * Export this and pass it to <CacheProvider> in your app root so that
 * extractCritical() on the server collects all generated styles.
 */
export const emotionCache = createCache({ key: 'css' });

/**
 * Server-side style extraction helper.
 * Call this in your SSR render pipeline (e.g. getServerSideProps or
 * a custom Express middleware) after renderToString():
 *
 *   const { html, css, ids } = extractCriticalToChunks(renderedHtml);
 *
 * @param {string} renderedHtml - The HTML string produced by renderToString()
 * @returns {{ css: string, ids: string[] }} Extracted critical CSS and cache IDs
 */
export function extractServerStyles(renderedHtml) {
  const { css, ids } = extractCritical(renderedHtml);
  return { css, ids };
}

// ---------------------------------------------------------------------------
// Styled components (unchanged business logic)
// ---------------------------------------------------------------------------

export const Button = styled.button`
  background: #0a2540;
  color: white;
  padding: 8px 16px;
`;

export const Card = styled.div`
  border: 1px solid #ddd;
  padding: 16px;
`;
