import { afterEach, describe, expect, it, vi } from "vitest";
import { isTauri } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { openExternalChecked } from "./external";

vi.mock("@tauri-apps/api/core", () => ({ isTauri: vi.fn(() => true) }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
afterEach(() => { vi.clearAllMocks(); vi.unstubAllGlobals(); });

describe("checked browser handoff", () => {
  it("preserves a signed URL exactly", async () => {
    const url = "https://cdn.example/file?signature=a%2Fb&part=1";
    await openExternalChecked(url);
    expect(openUrl).toHaveBeenCalledWith(url);
  });
  it("reports a native refusal to its caller", async () => {
    vi.mocked(openUrl).mockRejectedValueOnce(new Error("refused"));
    await expect(openExternalChecked("https://cdn.example/file")).rejects.toThrow("refused");
  });
  it.each(["file:///etc/passwd", "javascript:alert(1)", "data:text/html,test", "/relative"])(
    "refuses non-web address %s before opening anything", async (url) => {
      await expect(openExternalChecked(url)).rejects.toThrow();
      expect(openUrl).not.toHaveBeenCalled();
    },
  );
  it("keeps browser development downloads out of the app and sends no referrer", async () => {
    vi.mocked(isTauri).mockReturnValueOnce(false);
    const open = vi.fn(() => null);
    vi.stubGlobal("window", { open });
    await openExternalChecked("https://cdn.example/file");
    expect(open).toHaveBeenCalledWith("https://cdn.example/file", "_blank", "noreferrer");
  });
});
