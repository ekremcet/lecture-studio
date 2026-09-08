/**
 * Oberik project as code. Idempotent: run it again and it only changes what differs.
 *
 *   npm run oberik:setup            apply
 *   npm run oberik:setup -- --dry   print the current state and the intended changes only
 */
import "dotenv/config";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { createProjectClient } from "@oberik/sdk";

const dry = process.argv.includes("--dry");
const { OBERIK_PROJECT_ID, OPENAI_API_KEY, OBERIK_DEFAULT_MODEL } = process.env;
const OBERIK_PROJECT_KEY = process.env.OBERIK_PROJECT_KEY || process.env.OBERIK_API_KEY;
if (!OBERIK_PROJECT_ID || !OBERIK_PROJECT_KEY) {
  console.error("Set OBERIK_PROJECT_ID and OBERIK_PROJECT_KEY (or OBERIK_API_KEY) in .env");
  process.exit(1);
}

const oberik = createProjectClient({ projectId: OBERIK_PROJECT_ID, projectKey: OBERIK_PROJECT_KEY });

const ORIGINS = ["http://127.0.0.1:3005"]; // the origin the Mac app's web views run under
// Cost control: route simple turns to the cheap model, keep the large one for real work.
// A request that names a model (the switcher in the chat) bypasses the tiers.
const MODEL_TIERS = { mode: "auto" as const, simple: "openai/gpt-5.6-luna", normal: "openai/gpt-5.6-sol", complex: "openai/gpt-5.6-sol" };
// Only what the app needs on top of the dashboard defaults. Nothing is narrowed here;
// the minted token narrows per session.
const CAPABILITIES = {
  allowChat: true,
  allowComputer: true,
  allowApprovals: true,
  allowAskUser: true,
  allowUiTools: true,
  allowTodo: true,
  inputModalities: ["file", "image"],
};

function log(title: string, value: unknown) {
  console.log(`\n== ${title} ==`);
  console.log(typeof value === "string" ? value : JSON.stringify(value, null, 2));
}

async function step<T>(title: string, fn: () => Promise<T>): Promise<T | undefined> {
  if (dry) {
    console.log(`[dry] would ${title}`);
    return undefined;
  }
  const r = await fn();
  console.log(`[ok]  ${title}`);
  return r;
}

async function main() {
  const proj = (await oberik.project.get()) as Record<string, unknown>;
  log("project", { name: proj.name, defaultModel: proj.defaultModel, modelTiers: proj.modelTiers, health: proj.health });
  const caps = await oberik.capabilities.get();
  log("capabilities (current)", caps);
  const providers = (await oberik.providers.list()) as Array<Record<string, unknown>>;
  log("providers (current)", providers);
  log("default model (current)", await oberik.defaultModel.get());
  log("model tiers (current)", await oberik.modelTiers.get());
  log("origins (current)", await oberik.origins.get());
  log("skills (current)", await oberik.skills.list());
  log("system prompt (current)", (await oberik.systemPrompt.get()).systemPrompt ?? "(none)");

  // 1. System prompt
  const prompt = (await readFile("skill-pack/system-prompt.md", "utf8")).trim();
  const current = ((await oberik.systemPrompt.get()).systemPrompt ?? "").trim();
  if (current !== prompt) await step("set system prompt", () => oberik.systemPrompt.set(prompt));
  else console.log("[=]   system prompt unchanged");

  // 2. Capability ceiling (merge semantics)
  const capDiff = Object.entries(CAPABILITIES).filter(([k, v]) => JSON.stringify(caps[k]) !== JSON.stringify(v));
  if (capDiff.length) {
    log("capability changes", Object.fromEntries(capDiff));
    await step("set capabilities", () => oberik.capabilities.set(CAPABILITIES));
  } else console.log("[=]   capabilities unchanged");

  // 3. Origins (union with what is there)
  const have = (await oberik.origins.get()).origins;
  const want = Array.from(new Set([...have, ...ORIGINS]));
  if (want.length !== have.length) await step(`set origins ${JSON.stringify(want)}`, () => oberik.origins.set(want));
  else console.log("[=]   origins unchanged");

  // 4. OpenAI provider, only when none exists and a key is given
  const hasOpenAI = providers.some((p) => JSON.stringify(p).toLowerCase().includes("openai"));
  if (!hasOpenAI && OPENAI_API_KEY) {
    const r = await step("register OpenAI provider", () =>
      oberik.providers.create({
        provider: "openai",
        models: ["gpt-4o", "text-embedding-3-small"],
        values: { api_key: OPENAI_API_KEY },
        label: "openai",
      }),
    );
    if (r) log("provider created", r);
  } else if (!hasOpenAI) {
    console.log("[!]   no OpenAI provider on the project and no OPENAI_API_KEY in .env; register one in the dashboard or add the key");
  } else console.log("[=]   OpenAI provider present");

  // 4b. Model tiers
  const tiers = await oberik.modelTiers.get();
  const tierDiff = (Object.keys(MODEL_TIERS) as Array<keyof typeof MODEL_TIERS>).filter((k) => tiers[k] !== MODEL_TIERS[k]);
  if (tierDiff.length) await step(`set model tiers ${JSON.stringify(MODEL_TIERS)}`, () => oberik.modelTiers.set(MODEL_TIERS));
  else console.log("[=]   model tiers unchanged");

  // 5. Default model, only when asked
  if (OBERIK_DEFAULT_MODEL) {
    const cur = (await oberik.defaultModel.get()).defaultModel;
    if (cur !== OBERIK_DEFAULT_MODEL) await step(`set default model ${OBERIK_DEFAULT_MODEL}`, () => oberik.defaultModel.set(OBERIK_DEFAULT_MODEL));
    else console.log("[=]   default model unchanged");
  }

  // 6. Skills plugin zip, when built
  const zip = "dist/marp-slides.zip";
  if (existsSync(zip)) {
    const bytes = new Uint8Array(await readFile(zip));
    const manifest = JSON.parse(await readFile("skill-pack/plugin.json", "utf8")) as { name: string };
    const existing = (await oberik.skills.list()) as Array<{ id: string; name: string }>;
    for (const p of existing.filter((p) => p.name === manifest.name)) {
      await step(`delete previous plugin ${p.name} (${p.id})`, () => oberik.skills.delete(p.id));
    }
    await step(`upload skills ${zip}`, () => oberik.skills.upload(bytes, { filename: "marp-slides.zip" }));
  } else console.log("[-]   no skill pack zip yet (dist/marp-slides.zip); skipping");

  const p = (await oberik.project.get()) as Record<string, unknown>;
  log("health", { health: p.health, detail: p.healthDetail, defaultModel: p.defaultModel });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
