import { defineConfig, loadEnv } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";

export default ({ mode }) => {
  process.env = { ...process.env, ...loadEnv(mode, process.cwd()) };
  return defineConfig({
    plugins: [svelte(), tailwindcss()],
    base: "",
    server: {
      port: 8080,
      open: true,
    },
    build: {
      minify: "esbuild",
      assetsDir: "",
    },
  });
};
