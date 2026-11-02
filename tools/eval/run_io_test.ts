// The eval through its real file I/O: run_fake_openrouter.ts as a subprocess, from a directory
// holding the paths the eval reads, under the permission flags of the command in run.ts's header.
import assert from "node:assert/strict";

const ENTRY = new URL("./run_fake_openrouter.ts", import.meta.url).pathname;
const DOCUMENTED_FLAGS = [
  "--allow-read",
  "--allow-write=tools/eval/spend.json,docs/eval,tools/eval/replies",
  "--allow-net=openrouter.ai",
  "--allow-env=OPENROUTER_API_KEY",
  "--env-file=supabase/functions/.env",
];

/** A repository root holding one candidate, an empty ledger, one sample and the env file. */
async function root(): Promise<string> {
  const dir = await Deno.makeTempDir();
  await Deno.mkdir(`${dir}/tools/eval/samples`, { recursive: true });
  await Deno.mkdir(`${dir}/supabase/functions`, { recursive: true });
  await Deno.writeTextFile(
    `${dir}/tools/eval/candidates.json`,
    JSON.stringify([{ label: "Cheap", primary: "^vendor/cheap$" }]),
  );
  await Deno.writeTextFile(
    `${dir}/tools/eval/spend.json`,
    JSON.stringify({ budgetUsd: 10, runs: [] }),
  );
  await Deno.writeTextFile(
    `${dir}/tools/eval/samples/01-a.json`,
    JSON.stringify({
      image: "01-a.jpg",
      cards: [{
        front: "apple",
        senses: [{ labels: [], meaning: "사과", examples: [] }],
      }],
    }),
  );
  await Deno.writeFile(
    `${dir}/tools/eval/samples/01-a.jpg`,
    new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]),
  );
  await Deno.writeTextFile(
    `${dir}/supabase/functions/.env`,
    "OPENROUTER_API_KEY=fake\n",
  );
  return dir;
}

Deno.test("the documented command records the run in the ledger, writes the report creating docs/eval, and keeps each reply", async () => {
  const dir = await root();
  try {
    await assert.rejects(Deno.stat(`${dir}/docs`), Deno.errors.NotFound);

    const result = await new Deno.Command("deno", {
      args: ["run", ...DOCUMENTED_FLAGS, ENTRY],
      cwd: dir,
      env: { NO_COLOR: "1" },
    }).output();
    const decoder = new TextDecoder();
    const output = decoder.decode(result.stdout) +
      decoder.decode(result.stderr);

    assert.equal(result.code, 0, output);
    const ledger = JSON.parse(
      await Deno.readTextFile(`${dir}/tools/eval/spend.json`),
    );
    assert.equal(ledger.runs.length, 1, output);
    assert.equal(ledger.runs[0].spentUsd, 0.001);
    assert.equal(ledger.runs[0].note, "prompt v10");
    assert.match(
      await Deno.readTextFile(`${dir}/docs/eval/extract-cards.md`),
      /\| Cheap \| 100\.0 \| 100\.0 \| 100\.0 \|/,
    );
    const runs = await Array.fromAsync(
      Deno.readDir(`${dir}/tools/eval/replies`),
    );
    assert.equal(runs.length, 1);
    const reply = JSON.parse(
      await Deno.readTextFile(
        `${dir}/tools/eval/replies/${runs[0].name}/cheap/01-a.json`,
      ),
    );
    assert.equal(reply.outcome, "cards");
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
