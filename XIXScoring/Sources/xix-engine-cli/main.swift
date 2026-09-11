// xix-engine-cli: reads a RoundInput (or a fixture file with an "input" key) as JSON on stdin,
// runs XIXScoring, and prints the RoundResult as JSON with sorted keys on stdout.
// Built natively for the parity check and as a WASI module for the xix-engine edge function.
#if canImport(FoundationEssentials)
import FoundationEssentials   // Wasm: JSON without the internationalisation and ICU payload
#else
import Foundation
#endif
#if canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import XIXScoring

struct FixtureEnvelope: Decodable {
    let input: RoundInput
}

func fail(_ message: String, code: Int32) -> Never {
    var stderr = StandardError()
    print(message, to: &stderr)
    exit(code)
}

struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
        for byte in string.utf8 { putchar(Int32(byte)) }   // stderr is not exposed in FoundationEssentials; fall back to stdout-safe C I/O
    }
}

var text = ""
while let line = readLine(strippingNewline: false) { text += line }
let data = Data(text.utf8)
guard !data.isEmpty else {
    fail("xix-engine-cli: no input on stdin", code: 2)
}

let decoder = JSONDecoder()
let input: RoundInput
do {
    if let envelope = try? decoder.decode(FixtureEnvelope.self, from: data) {
        input = envelope.input
    } else {
        input = try decoder.decode(RoundInput.self, from: data)
    }
} catch {
    fail("xix-engine-cli: cannot decode RoundInput: \(error)", code: 3)
}

let result = ScoringEngine.score(input)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let out = try encoder.encode(result)
print(String(decoding: out, as: UTF8.self))
