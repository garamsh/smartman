/* tslint:disable */
/* eslint-disable */
/**
 * A card's state after a review, and when it is next due.
 */
export interface Scheduled {
    /**
     * The new memory state.
     */
    state: MemoryStateParts;
    /**
     * When the card is next due.
     */
    due: bigint;
}

/**
 * A floating-point quantity the engine takes.
 */
export type Quantity = "stability" | "difficulty" | "fuzzFactor";

/**
 * One review in a card's history.
 */
export interface ReviewRecord {
    /**
     * The answer given.
     */
    answer: Answer;
    /**
     * When it was given.
     */
    at: bigint;
}

/**
 * The app's two answer buttons.
 */
export type Answer = "know" | "dontKnow";

/**
 * The parts of a card's memory state that a caller persists.
 */
export interface MemoryStateParts {
    /**
     * Days until retrievability falls to 0.9.
     */
    stability: number;
    /**
     * Difficulty, from 1 to 10.
     */
    difficulty: number;
    /**
     * Time of the review that produced this state.
     */
    lastReview: bigint;
}

/**
 * What an operation returns: its value under `ok`, or the engine's refusal under `error`.
 */
export type Outcome<T> = { ok: T } | { error: EngineError };

/**
 * Why the engine refused its input; one variant per engine `Error` variant, told apart by `kind`.
 */
export type EngineError = { kind: "reviewBeforeLastReview"; lastReview: bigint; review: bigint } | { kind: "unknownRating"; value: number } | { kind: "nonFinite"; quantity: Quantity } | { kind: "outOfRange"; quantity: Quantity; value: number };


/**
 * Replays a history, in the order the reviews happened, into the card's state; `null` when empty.
 */
export function replay(history: ReviewRecord[]): Outcome<MemoryStateParts | null>;

/**
 * Probability of recall at `at` of a card whose state the caller persisted as `state`.
 */
export function retrievability(state: MemoryStateParts, at: bigint): Outcome<number>;

/**
 * Reviews a card whose state the caller persisted as `state`, its interval fuzzed by
 * the fuzz factor, a value in `[0, 1)`, or not fuzzed when it is absent.
 */
export function reviewCard(state: MemoryStateParts, answer: Answer, at: bigint, fuzzFactor?: number | null): Outcome<Scheduled>;

/**
 * Reviews a new card for the first time, its interval fuzzed by the fuzz factor, a value
 * in `[0, 1)`, or not fuzzed when it is absent.
 */
export function reviewNewCard(answer: Answer, at: bigint, fuzzFactor?: number | null): Outcome<Scheduled>;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly replay: (a: number, b: number) => [number, number, number];
    readonly retrievability: (a: any, b: bigint) => [number, number, number];
    readonly reviewCard: (a: any, b: any, c: bigint, d: number, e: number) => [number, number, number];
    readonly reviewNewCard: (a: any, b: bigint, c: number, d: number) => [number, number, number];
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __externref_table_alloc: () => number;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
