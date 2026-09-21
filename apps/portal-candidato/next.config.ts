import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // O repositório tem mais de um package-lock.json; fixa a raiz do Turbopack neste app.
  turbopack: { root: path.resolve(__dirname) },
};

export default nextConfig;
