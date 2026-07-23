import AeroControlKit
import Common
import Foundation

// Separate performance harness for AeroSpace command transport. It measures the
// real command path through the `AerospaceProcessRunner` port so competing
// implementations (CLI process-spawn today, a Unix-socket runner later) can be
// benchmarked A/B with identical scenarios. NOT shipped in the app — excluded
// from the production code-metrics gate.

struct Options {
    var runner = "socket"
    var scenario = "refresh"
    var iterations = 50
    var warmup = 5
    var delayMs = 0
}

func parseOptions() -> Options {
    var opts = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--runner": opts.runner = it.next() ?? opts.runner
        case "--scenario": opts.scenario = it.next() ?? opts.scenario
        case "--iterations", "-n": opts.iterations = Int(it.next() ?? "") ?? opts.iterations
        case "--warmup", "-w": opts.warmup = Int(it.next() ?? "") ?? opts.warmup
        case "--delay-ms", "-d": opts.delayMs = Int(it.next() ?? "") ?? opts.delayMs
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
            printUsage()
            exit(2)
        }
    }
    return opts
}

func printUsage() {
    print(
        """
        PerfBench — AeroSpace command-transport benchmark

        Usage: swift run -c release PerfBench [options]

          --runner <cli>            transport under test (default: cli)
          --scenario <name>         list-windows | list-workspaces | refresh (default: refresh)
                                    'refresh' = list-windows + list-workspaces (the hot read path)
          --iterations, -n <int>    measured iterations (default: 50)
          --warmup, -w <int>        unmeasured warmup iterations (default: 5)
          --delay-ms, -d <int>      idle gap between iterations (default: 0), models
                                    real-app spacing where calls arrive seconds apart

        Scenarios are read-only and safe to repeat. Fire-and-forget commands
        (focus/move/close) are intentionally excluded — they mutate live state.
        """
    )
}

func makeRunner(_ name: String) -> AerospaceProcessRunner {
    switch name {
    case "socket":
        return AerospaceSocketRunner()
    default:
        FileHandle.standardError.write(Data("Unknown runner '\(name)'. Known: socket\n".utf8))
        exit(2)
    }
}

func argvBatches(for scenario: String) -> [[String]] {
    switch scenario {
    case "list-windows": return [AerospaceCommand.listWindows()]
    case "list-workspaces": return [AerospaceCommand.listWorkspaces()]
    case "refresh": return [AerospaceCommand.listWindows(), AerospaceCommand.listWorkspaces()]
    default:
        FileHandle.standardError.write(Data("Unknown scenario '\(scenario)'.\n".utf8))
        exit(2)
    }
}

func seconds(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = p / 100 * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = Int(rank.rounded(.up))
    if lo == hi { return sorted[lo] }
    let frac = rank - Double(lo)
    return sorted[lo] * (1 - frac) + sorted[hi] * frac
}

func fmt(_ ms: Double) -> String { unsafe String(format: "%8.2f", ms) }

let opts = parseOptions()
let runner = makeRunner(opts.runner)

if opts.scenario == "subscribe-probe" {
    // De-risk: stream real ServerEvents over the socket and print the first few,
    // to confirm the wire format matches AerospaceEvent.parse.
    print("subscribe-probe · runner=\(opts.runner) — waiting for \(opts.iterations) events (switch workspaces to generate some)…")
    var seen = 0
    let stream = runner.subscribe(AerospaceCommand.subscribe())
    do {
        for try await line in stream {
            print("EVENT: \(line)")
            seen += 1
            if seen >= opts.iterations { break }
        }
    } catch {
        FileHandle.standardError.write(Data("subscribe failed: \(error)\n".utf8))
        exit(1)
    }
    print("subscribe-probe done (\(seen) events)")
    exit(0)
}

let batches = argvBatches(for: opts.scenario)
let clock = ContinuousClock()

// One measured iteration runs every argv batch in the scenario sequentially,
// mirroring how a single refresh issues its CLI calls.
func runIteration() async throws {
    for args in batches {
        _ = try await runner.run(args)
    }
}

// Sanity check + warmup (also verifies AeroSpace is reachable before timing).
do {
    let first = try await runner.run(batches[0])
    if CommandLine.arguments.contains("--dump") {
        // Correctness aid: print the exact stdout the runner produced, so a
        // socket run can be diffed byte-for-byte against a CLI run.
        print(first)
        exit(0)
    }
} catch {
    FileHandle.standardError.write(Data("Precheck failed (is AeroSpace running?): \(error)\n".utf8))
    exit(1)
}
for _ in 0 ..< max(0, opts.warmup - 1) { _ = try? await runIteration() }

var samplesMs: [Double] = []
samplesMs.reserveCapacity(opts.iterations)
let wallStart = clock.now
for _ in 0 ..< opts.iterations {
    let start = clock.now
    try await runIteration()
    samplesMs.append(seconds(clock.now - start) * 1000)
    if opts.delayMs > 0 { try? await Task.sleep(for: .milliseconds(opts.delayMs)) }
}
let wallMs = seconds(clock.now - wallStart) * 1000

let sorted = samplesMs.sorted()
let mean = samplesMs.reduce(0, +) / Double(samplesMs.count)
let variance = samplesMs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samplesMs.count)
let stddev = variance.squareRoot()
let perSecond = 1000.0 / mean

print("")
print("PerfBench · runner=\(opts.runner) · scenario=\(opts.scenario) · n=\(opts.iterations) (warmup \(opts.warmup))")
print("  batches/iter: \(batches.count)  (\(batches.map { $0.first ?? "?" }.joined(separator: " + ")))")
print("  ---------------------------------------------")
print("  min    \(fmt(sorted.first ?? 0)) ms")
print("  median \(fmt(percentile(sorted, 50))) ms")
print("  mean   \(fmt(mean)) ms   (± \(fmt(stddev)) stddev)")
print("  p95    \(fmt(percentile(sorted, 95))) ms")
print("  p99    \(fmt(percentile(sorted, 99))) ms")
print("  max    \(fmt(sorted.last ?? 0)) ms")
print("  ---------------------------------------------")
print("  throughput ~\(unsafe String(format: "%.1f", perSecond)) iter/s   wall \(fmt(wallMs)) ms")
print("")
