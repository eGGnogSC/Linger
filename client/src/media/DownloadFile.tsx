import { useState } from "react";
import { openExternalChecked } from "../lib/external";

/** Keep untrusted bytes in the browser and make a refused handoff recoverable. */
export default function DownloadFile({ url }: { url: string }) {
  const [phase, setPhase] = useState<"idle" | "opening" | "requested" | "failed">("idle");
  const download = async (): Promise<void> => {
    setPhase("opening");
    try {
      await openExternalChecked(url);
      setPhase("requested");
    } catch {
      // Native errors may contain signed media URLs or desktop details. Show
      // the recovery action, not the underlying error or a diagnostic log.
      setPhase("failed");
    }
  };
  return (
    <span className="att-download">
      <button type="button" className="att-get" disabled={phase === "opening"} onClick={() => void download()}>
        {phase === "opening" ? "opening browser…" : "download in browser"}
      </button>
      {phase === "failed" || phase === "requested" ? (
        <>
          <span className="att-download-note" role={phase === "failed" ? "alert" : "status"}>
            {phase === "failed"
              ? "Couldn't open your browser. Try again, or copy this link into your browser."
              : "Check your browser's downloads. If nothing opened, copy this link into your browser."}
          </span>
          <input className="att-download-url" aria-label="download link" readOnly value={url}
            onFocus={(event) => event.currentTarget.select()} />
        </>
      ) : null}
    </span>
  );
}
