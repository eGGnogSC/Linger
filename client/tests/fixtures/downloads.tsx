import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { mockIPC } from "@tauri-apps/api/mocks";
import type { Attachment } from "../../src/generated/Attachment";
import type { MediaItem } from "../../src/generated/MediaItem";
import { AuthedApi } from "../../src/lib/api";
import Attachments from "../../src/media/Attachments";
import MediaPanel from "../../src/media/MediaPanel";
import "../../src/fonts/fonts.css";
import "../../src/styles/tokens.css";
import "../../src/styles/base.css";

const params = new URLSearchParams(location.search);
const baseUrl = "https://app.example";
const file: Attachment = {
  id: "file", filename: "notes.txt", mime: "text/plain", size_bytes: 12,
  url: params.has("relative") ? "/objects/file" : "https://cdn.example/objects/file?signature=a%2Fb&part=1",
  width: null, height: null, duration_ms: null, blurhash: null, poster_url: null,
  starred_at: null, uploader_id: "fixture", created_at: 0,
};
const item: MediaItem = {
  kind: "file", cursor: "file", author_id: "fixture", created_at: 0,
  message_id: "message", room_id: "room", attachment: file, link: null,
  excerpt: null, starred_at: null,
};

// Exercise both production surfaces, but never launch the developer's browser.
Object.defineProperty(globalThis, "isTauri", { value: true });
mockIPC(async (cmd, payload) => {
  if (cmd !== "plugin:opener|open_url" || !payload || !("url" in payload)) {
    throw new Error("unexpected fixture command");
  }
  if (typeof payload.url !== "string") throw new Error("missing fixture URL");
  document.documentElement.dataset.requestedUrl = payload.url;
  if (document.documentElement.dataset.refuseOpen !== "no") throw new Error("fixture refusal");
});
const api = new AuthedApi(baseUrl, {
  accessToken: "fixture", refreshToken: "fixture", expiresAt: Date.now() + 60_000,
}, { onTokens: () => {}, onSignedOut: () => {} });
api.media = async () => [item];

const root = document.getElementById("root");
if (!root) throw new Error("missing fixture root");
createRoot(root).render(
  <StrictMode>
    {params.get("surface") === "media" ? (
      <MediaPanel api={api} users={[]} me="fixture" rooms={[]} onOpen={() => {}} onClose={() => {}} />
    ) : <Attachments files={[file]} baseUrl={baseUrl} />}
  </StrictMode>,
);
