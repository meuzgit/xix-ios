// xix-engine: the authoritative scoring run (Build Doc 2 B.2).
//
// Invoked by a Database Webhook on xix.engine_queue insert ({ record: { round_id } }) or directly with
// { "round_id": "..." }. Loads RoundInput via xix.round_input, runs XIXScoring compiled to WebAssembly
// (the same package the app runs natively; parity is checked in CI), and hands the RoundResult to
// xix.apply_engine_result, which stores it, awards medals idempotently, refreshes Levels and consumes
// the queue row. Failures are recorded with xix.engine_run_failed (five strikes, then dead-letter).
import { createClient } from "npm:@supabase/supabase-js@2.47.10";
import { WASI, File, OpenFile, PreopenDirectory } from "npm:@bjorn3/browser_wasi_shim@0.3.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ENGINE_VERSION_KEY = "engineVersion";

const wasmBytes = await Deno.readFile(new URL("./xix-engine-cli.wasm", import.meta.url));
const wasmModule = await WebAssembly.compile(wasmBytes);

/** Runs the engine once: RoundInput JSON in, RoundResult JSON out. */
export async function runEngine(input: unknown): Promise<Record<string, unknown>> {
  const stdin = new OpenFile(new File(new TextEncoder().encode(JSON.stringify(input))));
  const stdout = new OpenFile(new File([]));
  const stderr = new OpenFile(new File([]));
  const wasi = new WASI(["xix-engine-cli"], [], [stdin, stdout, stderr, new PreopenDirectory(".", new Map())]);
  const instance = await WebAssembly.instantiate(wasmModule, { wasi_snapshot_preview1: wasi.wasiImport });
  const code = wasi.start(instance as { exports: { memory: WebAssembly.Memory; _start: () => unknown } });
  const out = new TextDecoder().decode(stdout.file.data);
  if (code !== 0 || !out.trim()) {
    throw new Error(`engine exited ${code}: ${new TextDecoder().decode(stderr.file.data) || out}`);
  }
  return JSON.parse(out);
}

Deno.serve(async (req) => {
  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { db: { schema: "xix" }, auth: { persistSession: false } });
  let roundID: string | undefined;
  try {
    const body = await req.json();
    roundID = body?.record?.round_id ?? body?.round_id;
  } catch {
    return Response.json({ error: "expected JSON with round_id" }, { status: 400 });
  }
  if (!roundID) return Response.json({ error: "round_id required" }, { status: 400 });

  try {
    const { data: input, error: inputError } = await db.rpc("round_input", { round_id: roundID });
    if (inputError) throw new Error(`round_input: ${inputError.message}`);
    const result = await runEngine(input);
    const version = Number(result[ENGINE_VERSION_KEY]);
    const { error: applyError } = await db.rpc("apply_engine_result", { round_id: roundID, version, payload: result });
    if (applyError) throw new Error(`apply_engine_result: ${applyError.message}`);
    return Response.json({ round_id: roundID, version, status: result.status });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await db.rpc("engine_run_failed", { round_id: roundID, error: message });
    return Response.json({ round_id: roundID, error: message }, { status: 500 });
  }
});
