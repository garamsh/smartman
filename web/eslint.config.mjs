import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import tseslint from "typescript-eslint";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Rules that need the type checker, over the TypeScript sources.
  {
    files: ["**/*.ts", "**/*.tsx"],
    extends: [tseslint.configs.strictTypeCheckedOnly],
    languageOptions: { parserOptions: { projectService: true } },
  },
  // A Server Action's unused first parameter is the previous state useActionState passes.
  {
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
  // A feature is reached only through index.ts and actions.ts; the foundations sit below every feature.
  {
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              regex: "^@/features/[^/]+/(?!index$|actions$)",
              message:
                "Import a feature through its index.ts or actions.ts (docs/architecture/structure.md).",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["src/design/**", "src/supabase/**", "src/env.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              regex: "^@/(features|app)/",
              message:
                "src/design/, src/supabase/ and src/env.ts import no feature or route (docs/architecture/structure.md).",
            },
          ],
        },
      ],
    },
  },
  globalIgnores([".next/**", "next-env.d.ts", "playwright-report/**", "test-results/**"]),
]);

export default eslintConfig;
