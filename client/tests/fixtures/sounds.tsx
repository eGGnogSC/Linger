import { createRoot } from "react-dom/client";
import { SoundSection } from "../../src/settings/SettingsPanel";
import "../../src/fonts/fonts.css";
import "../../src/styles/tokens.css";
import "../../src/styles/base.css";

const root = document.getElementById("root");
if (!root) throw new Error("missing fixture root");
createRoot(root).render(<SoundSection />);
