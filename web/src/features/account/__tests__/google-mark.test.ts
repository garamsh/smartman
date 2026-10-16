// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const root = path.join(import.meta.dirname, "../../../../..");

describe("the web's Google G mark", () => {
  it.each(["light", "dark"])(
    "is the app's %s mark from Google's bundle, byte for byte, at 4x",
    (theme) => {
      const web = readFileSync(path.join(root, `web/public/google/g-mark-${theme}.png`));
      const app = readFileSync(path.join(root, `app/assets/google/4.0x/g_mark_${theme}.png`));

      // Control: an 80 px PNG, the 4x of the guidelines' 20 px mark.
      expect(app.subarray(1, 4).toString()).toBe("PNG");
      expect([app.readUInt32BE(16), app.readUInt32BE(20)]).toEqual([80, 80]);
      expect(web.equals(app)).toBe(true);
    },
  );
});
