import path from "node:path";

import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  // The container runs .next/standalone/server.js (Dockerfile).
  output: "standalone",
  experimental: {
    // src/styles/fonts is a link to the app's bundled fonts, outside this project.
    turbopackAdditionalRoots: {
      fonts: { path: path.join(import.meta.dirname, "../app/assets/fonts") },
    },
  },
};

export default nextConfig;
