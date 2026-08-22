/**
 * Card.js — Emotion styled components with SSR critical-CSS extraction
 *
 * For Fargate / Kubernetes SSR deployments (e.g. Next.js, Angular Universal)
 * all Emotion styles must be extracted on the server so they are inlined in
 * the initial HTML response, preventing Flash of Unstyled Content (FOUC).
 *
 * How it works:
 *  1. A fresh `EmotionCacheProvider` is created per request using
 *     `createCache` from `@emotion/cache`.
 *  2. `createEmotionServer` from `@emotion/server` wraps the cache and
 *     exposes `extractCriticalToChunks` / `constructStyleTagsFromChunks`.
 *  3. The SSR helper (`renderWithEmotionSSR`) renders the React tree to an
 *     HTML string, extracts the critical style chunks, and returns both the
 *     markup and the ready-to-inject <style> tags.
 *  4. The caller (e.g. a Next.js custom `_document.js` or an Express SSR
 *     handler) injects `styleTags` into the <head> before sending the
 *     response — ensuring styles are present on first paint inside the pod.
 *
 * Dependencies required (add to package.json):
 *   "@emotion/cache": "^11.x"
 *   "@emotion/server": "^11.x"
 *   "@emotion/styled": "^11.x"
 *   "@emotion/react": "^11.x"
 *   "react-dom": "^18.x"
 */

import styled from '@emotion/styled';
import createCache from '@emotion/cache';
import createEmotionServer from '@emotion/server/create-instance';
import { renderToString } from 'react-dom/server';
import { CacheProvider } from '@emotion/react';
import React from 'react';

// ---------------------------------------------------------------------------
// Styled components
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

// ---------------------------------------------------------------------------
// SSR critical-CSS extraction helper (Fargate / container SSR tasks)
// ---------------------------------------------------------------------------

/**
 * Creates a fresh per-request Emotion cache and the matching server instance.
 * A new cache MUST be created for every SSR request to avoid cross-request
 * style leakage between concurrent Fargate task invocations.
 *
 * @returns {{ cache: EmotionCache, emotionServer: EmotionServer }}
 */
export function createEmotionSSRContext() {
  const cache = createCache({ key: 'css' });
  const emotionServer = createEmotionServer(cache);
  return { cache, emotionServer };
}

/**
 * Renders a React element to an HTML string and extracts all critical Emotion
 * styles needed for that render.  The returned `styleTags` string must be
 * injected into the <head> of the SSR response before it is sent to the
 * client.
 *
 * Usage in an Express / custom-server SSR handler:
 *
 *   import { renderWithEmotionSSR } from './components/Card';
 *
 *   app.get('*', (req, res) => {
 *     const { html, styleTags } = renderWithEmotionSSR(<App />);
 *     res.send(`
 *       <!DOCTYPE html>
 *       <html>
 *         <head>${styleTags}</head>
 *         <body><div id="root">${html}</div></body>
 *       </html>
 *     `);
 *   });
 *
 * Usage in a Next.js custom _document.js:
 *
 *   import Document, { Html, Head, Main, NextScript } from 'next/document';
 *   import { createEmotionSSRContext } from './components/Card';
 *   import { extractCriticalToChunks, constructStyleTagsFromChunks }
 *     from '@emotion/server';
 *
 *   export default class MyDocument extends Document {
 *     static async getInitialProps(ctx) {
 *       const { cache, emotionServer } = createEmotionSSRContext();
 *       const originalRenderPage = ctx.renderPage;
 *       ctx.renderPage = () =>
 *         originalRenderPage({
 *           enhanceApp: (App) => (props) =>
 *             <CacheProvider value={cache}><App {...props} /></CacheProvider>,
 *         });
 *       const initialProps = await Document.getInitialProps(ctx);
 *       const emotionStyles = emotionServer.extractCriticalToChunks(
 *         initialProps.html
 *       );
 *       const emotionStyleTags =
 *         emotionServer.constructStyleTagsFromChunks(emotionStyles);
 *       return { ...initialProps, emotionStyleTags };
 *     }
 *   }
 *
 * @param {React.ReactElement} element - The root React element to render.
 * @returns {{ html: string, styleTags: string }}
 */
export function renderWithEmotionSSR(element) {
  const { cache, emotionServer } = createEmotionSSRContext();

  // Wrap the element in the per-request CacheProvider so every styled
  // component uses the isolated cache for this render pass.
  const wrappedElement = React.createElement(
    CacheProvider,
    { value: cache },
    element
  );

  // Render to HTML string — this populates the Emotion cache with all styles
  // referenced during the render.
  const html = renderToString(wrappedElement);

  // Extract the critical CSS chunks that were actually used in this render.
  const chunks = emotionServer.extractCriticalToChunks(html);

  // Build ready-to-inject <style> tag(s) from the extracted chunks.
  const styleTags = emotionServer.constructStyleTagsFromChunks(chunks);

  return { html, styleTags };
}
