/** The theme the user picks on the account page: the system's, light, or dark. */
export type ThemeChoice = "system" | "light" | "dark";

/** Where this browser keeps the choice; absent is the system's. */
export const themeStorageKey = "smartman.theme";

/** The choice a stored value names; anything else, absence included, is the system's. */
export function parseThemeChoice(stored: string | null): ThemeChoice {
  return stored === "light" || stored === "dark" ? stored : "system";
}

/**
 * Draws the page in [choice]: `data-theme` on the root element names a light or dark choice,
 * and its absence lets `prefers-color-scheme` decide (globals.css).
 */
export function applyThemeChoice(root: HTMLElement, choice: ThemeChoice) {
  if (choice === "system") delete root.dataset.theme;
  else root.dataset.theme = choice;
}

/**
 * The script the root layout puts first in `<head>`. It runs before the body is parsed, so the
 * first paint already has the stored theme. Storage that cannot be read leaves the system's.
 */
export const themeScript = `try{var t=localStorage.getItem(${JSON.stringify(themeStorageKey)});if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

/** Why a choice could not be kept: this browser refused to store it. */
export type ThemeStoreFailure = "unstorable";

/** Keeps [choice] on this browser, or says it could not. */
export function storeThemeChoice(storage: Storage, choice: ThemeChoice): ThemeStoreFailure | null {
  try {
    if (choice === "system") storage.removeItem(themeStorageKey);
    else storage.setItem(themeStorageKey, choice);
    return null;
  } catch {
    // A private window, a full quota or storage blocked by the user.
    return "unstorable";
  }
}

/** The choice this browser keeps; storage that cannot be read is the system's. */
export function readThemeChoice(storage: Storage): ThemeChoice {
  try {
    return parseThemeChoice(storage.getItem(themeStorageKey));
  } catch {
    return "system";
  }
}
