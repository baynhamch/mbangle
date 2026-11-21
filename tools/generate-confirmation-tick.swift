#!/usr/bin/env swift
import Foundation

// Original, deterministic confirmation sound for mbangle. Three damped tones
// give the tick a soft tactile character, with no samples or third-party audio.
// Render from the repository root: swift tools/generate-confirmation-tick.swift
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "mbangle/Resources/AlignmentTick.wav")
let sampleRate = 44_100
let duration = 0.08
let sampleCount = Int(Double(sampleRate) * duration)
let attack = 0.003
let fadeStart = 0.06
let peakLevel = 0.62

let waveform: [Double] = (0..<sampleCount).map { sample in
    let time = Double(sample) / Double(sampleRate)
    let rise = pow(sin(.pi / 2 * min(time / attack, 1)), 2)
    let decay = exp(-max(0, time - attack) / 0.014)
    let fadePosition = max(0, (time - fadeStart) / (duration - fadeStart))
    let tail = 0.5 * (1 + cos(.pi * fadePosition))
    let tone = sin(2 * .pi * 1_310 * time)
        + 0.30 * sin(2 * .pi * 2_180 * time)
        + 0.12 * sin(2 * .pi * 3_370 * time)
    return tone * rise * decay * tail
}
let peak = waveform.map { abs($0) }.max()!
let samples = waveform.map { Int16(($0 / peak * peakLevel * Double(Int16.max)).rounded()) }

func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

// RIFF/WAVE, mono, 16-bit linear PCM. The smooth attack and tail avoid a
// discontinuity at either edge; playback gain is chosen by the app.
let audioByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
var data = Data("RIFF".utf8)
append(UInt32(36) + audioByteCount, to: &data)
data.append(contentsOf: "WAVEfmt ".utf8)
append(UInt32(16), to: &data) // PCM format chunk length.
append(UInt16(1), to: &data) // Linear PCM.
append(UInt16(1), to: &data) // Mono.
append(UInt32(sampleRate), to: &data)
append(UInt32(sampleRate * 2), to: &data)
append(UInt16(2), to: &data) // Block alignment.
append(UInt16(16), to: &data)
data.append(contentsOf: "data".utf8)
append(audioByteCount, to: &data)
for sample in samples { append(sample, to: &data) }

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output, options: .atomic)
print("Rendered \(samples.count) mono PCM samples (80 ms) to \(output.path).")
