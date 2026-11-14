import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const RAILS_URL = "http://localhost:3000";

// If Rails isn't running, answer with a JSON 503 instead of Vite's default bare 500.
function handleProxyErrors(proxy) {
  proxy.on("error", (err, _req, res) => {
    if (!res || res.headersSent || typeof res.writeHead !== "function") return;
    res.writeHead(503, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        error: {
          code: "api_unavailable",
          message: "Can't reach the API server. Start it with bin/dev (or bin/rails server).",
        },
      })
    );
  });
}

// Rails API runs on :3000; Vite dev server runs on :5173 and proxies API calls.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: RAILS_URL, configure: handleProxyErrors },
      "/up": { target: RAILS_URL, configure: handleProxyErrors },
      // Action Cable WebSocket: pushes summary status changes instead of the card polling.
      "/cable": { target: RAILS_URL, ws: true },
    },
  },
});
