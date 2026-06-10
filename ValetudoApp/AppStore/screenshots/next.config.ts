import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Pin the workspace root to THIS folder.
  // Otherwise Turbopack walks up, finds ~/Documents/package-lock.json,
  // and watches the entire Documents tree → CPU/RAM meltdown.
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
