import { loadAppConfig } from "./sync/appConfig";

export const config = loadAppConfig();

// Product toggle: keep Gemini backend support available, but hide Gemini-specific UI.
export const SHOW_GEMINI_UI = false;
