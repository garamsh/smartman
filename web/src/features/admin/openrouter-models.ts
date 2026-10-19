import "server-only";

/** OpenRouter's public model list, which names each model's inputs and supported parameters. */
export const openRouterModelsUrl = "https://openrouter.ai/api/v1/models";

/** Whether a model id may serve a plan, or why it may not. */
export type ModelCheck = "usable" | "unknown" | "unsuitable" | "unreachable";

/**
 * Whether OpenRouter lists [model] as one extract-cards can call: taking image input and
 * supporting structured outputs, the rule the eval applies (`tools/eval/models.ts`).
 */
export async function checkModel(model: string): Promise<ModelCheck> {
  let body: unknown;
  try {
    const response = await fetch(openRouterModelsUrl, { signal: AbortSignal.timeout(20_000) });
    if (!response.ok) return "unreachable";
    body = await response.json();
  } catch {
    return "unreachable";
  }
  const data = typeof body === "object" && body !== null && "data" in body ? body.data : null;
  if (!Array.isArray(data)) return "unreachable";
  const entry: unknown = data.find(
    (candidate: unknown) =>
      typeof candidate === "object" &&
      candidate !== null &&
      "id" in candidate &&
      candidate.id === model,
  );
  if (typeof entry !== "object" || entry === null) return "unknown";
  const inputs =
    "architecture" in entry &&
    typeof entry.architecture === "object" &&
    entry.architecture !== null &&
    "input_modalities" in entry.architecture
      ? entry.architecture.input_modalities
      : null;
  const parameters = "supported_parameters" in entry ? entry.supported_parameters : null;
  return Array.isArray(inputs) &&
    inputs.includes("image") &&
    Array.isArray(parameters) &&
    parameters.includes("structured_outputs")
    ? "usable"
    : "unsuitable";
}
