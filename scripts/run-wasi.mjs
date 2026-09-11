// Run a WASI command module: stdin from a file, stdout to our stdout. Usage: node run-wasi.mjs module.wasm input.json
import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";
import { openSync, closeSync, readFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [wasmPath, inputPath] = process.argv.slice(2);
const outPath = join(tmpdir(), `xix-wasi-${process.pid}-${Date.now()}.out`);
const inFd = openSync(inputPath, "r");
const outFd = openSync(outPath, "w");
const wasi = new WASI({ version: "preview1", args: ["xix-engine-cli"], env: {}, stdin: inFd, stdout: outFd, stderr: 2, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(wasmPath));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
const code = wasi.start(instance);
closeSync(inFd); closeSync(outFd);
process.stdout.write(readFileSync(outPath, "utf8"));
unlinkSync(outPath);
process.exit(code);
