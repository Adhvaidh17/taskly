import {
  INTENT_MODEL_BASE64,
  INTENT_MODEL_BIAS,
  INTENT_MODEL_DIM,
  INTENT_MODEL_METADATA,
  INTENT_MODEL_SCALE,
} from "./intent_model_weights.ts";

export type IntentModelResult = {
  taskProbability: number;
  nonTaskProbability: number;
  modelVersion: string;
  featureCount: number;
};

let cachedWeights: Int16Array | null = null;

function decodeWeights(): Int16Array {
  if (cachedWeights) return cachedWeights;
  const binary = atob(INTENT_MODEL_BASE64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  if (bytes.byteLength !== INTENT_MODEL_DIM * 2) {
    throw new Error(`Intent model size mismatch: ${bytes.byteLength}`);
  }
  cachedWeights = new Int16Array(bytes.buffer);
  return cachedWeights;
}

function normaliseText(value: string): string {
  return value
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[’‘`]/g, "'")
    .replace(/https?:\/\/\S+/giu, " url ")
    .replace(/\s+/g, " ")
    .trim()
    .toLocaleLowerCase();
}

function fnv1a(value: string): number {
  let hash = 0x811c9dc5;
  const bytes = new TextEncoder().encode(value);
  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

function addFeature(map: Map<number, number>, token: string, amount: number): void {
  const hash = fnv1a(token);
  const index = hash % INTENT_MODEL_DIM;
  const sign = (hash & 0x80000000) === 0 ? 1 : -1;
  map.set(index, (map.get(index) ?? 0) + amount * sign);
}

function featureMap(rawText: string): Map<number, number> {
  const text = `^${normaliseText(rawText)}$`;
  const result = new Map<number, number>();
  for (const n of [3, 4, 5]) {
    for (let i = 0; i <= text.length - n; i += 1) {
      addFeature(result, `c${text.slice(i, i + n)}`, 1);
    }
  }
  const words = text.match(/[\p{L}\p{N}_']+/gu) ?? [];
  for (const n of [1, 2]) {
    for (let i = 0; i <= words.length - n; i += 1) {
      addFeature(result, `w${words.slice(i, i + n).join("_")}`, 1.6);
    }
  }
  let squared = 0;
  for (const value of result.values()) squared += value * value;
  const norm = Math.sqrt(squared) || 1;
  for (const [index, value] of result) result.set(index, value / norm);
  return result;
}

function sigmoid(value: number): number {
  if (value >= 0) {
    const z = Math.exp(-value);
    return 1 / (1 + z);
  }
  const z = Math.exp(value);
  return z / (1 + z);
}

export function classifyTaskIntent(text: string): IntentModelResult {
  const features = featureMap(text);
  const weights = decodeWeights();
  let score = INTENT_MODEL_BIAS;
  for (const [index, value] of features) {
    score += weights[index]! * INTENT_MODEL_SCALE * value;
  }
  const taskProbability = Math.max(0, Math.min(1, sigmoid(score)));
  return {
    taskProbability,
    nonTaskProbability: 1 - taskProbability,
    modelVersion: INTENT_MODEL_METADATA.version,
    featureCount: features.size,
  };
}
