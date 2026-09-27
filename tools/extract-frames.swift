// Converts a green-screen walk-in-place video into transparent PNG frames.
//
// Usage:
//   swiftc -O -o /tmp/extract-frames tools/extract-frames.swift
//   /tmp/extract-frames cat_moving.mp4 art/cat
//
// Steps: chroma-key the green, despill edges, crop every frame to the union
// bounding box of the subject, detect the walk-cycle loop length, and write
// frames 0..<loop as art/cat/cat_000.png, cat_001.png, ...
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: extract-frames <video> <outdir>\n".data(using: .utf8)!)
    exit(1)
}
let videoURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

struct RGBA { var data: [UInt8]; let w: Int; let h: Int }

func pixels(of image: CGImage) -> RGBA {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return RGBA(data: data, w: w, h: h)
}

// Alpha from green dominance (g - max(r, b)); soft ramp between lo and hi.
// Green spill on semi-transparent edges is clamped to max(r, b).
func key(_ img: inout RGBA) {
    let lo = 0.10, hi = 0.30
    for i in stride(from: 0, to: img.data.count, by: 4) {
        let r = Double(img.data[i]) / 255, g = Double(img.data[i + 1]) / 255, b = Double(img.data[i + 2]) / 255
        let dominance = g - max(r, b)
        let a = dominance <= lo ? 1.0 : (dominance >= hi ? 0.0 : 1.0 - (dominance - lo) / (hi - lo))
        let gDespilled = min(g, max(r, b))
        img.data[i]     = UInt8((r * a * 255).rounded())
        img.data[i + 1] = UInt8((gDespilled * a * 255).rounded())
        img.data[i + 2] = UInt8((b * a * 255).rounded())
        img.data[i + 3] = UInt8((a * 255).rounded())
    }
}

func bbox(_ img: RGBA) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<img.h {
        for x in 0..<img.w where img.data[(y * img.w + x) * 4 + 3] > 16 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return maxX < 0 ? nil : (minX, minY, maxX, maxY)
}

// Mean absolute alpha difference inside a crop rect.
func diff(_ a: RGBA, _ b: RGBA, _ r: CGRect) -> Double {
    var sum = 0, n = 0
    for y in Int(r.minY)..<Int(r.maxY) {
        for x in Int(r.minX)..<Int(r.maxX) {
            let i = (y * a.w + x) * 4 + 3
            sum += abs(Int(a.data[i]) - Int(b.data[i])); n += 1
        }
    }
    return Double(sum) / Double(max(1, n))
}

func writePNG(_ img: RGBA, crop: CGRect, to url: URL) {
    var d = img.data
    let ctx = CGContext(data: &d, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = ctx.makeImage()!
    let cropped = full.cropping(to: crop)!
    let rep = NSBitmapImageRep(cgImage: cropped)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Read + key every frame

let asset = AVURLAsset(url: videoURL)
let track = asset.tracks(withMediaType: .video)[0]
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
reader.add(output)
reader.startReading()

let ciContext = CIContext()
var frames: [RGBA] = []
while let sample = output.copyNextSampleBuffer(), let buf = CMSampleBufferGetImageBuffer(sample) {
    let ci = CIImage(cvPixelBuffer: buf)
    let cg = ciContext.createCGImage(ci, from: ci.extent)!
    var px = pixels(of: cg)
    key(&px)
    frames.append(px)
}
print("read \(frames.count) frames @ \(track.nominalFrameRate) fps")

// MARK: - Union bbox (+ padding)

var ux0 = Int.max, uy0 = Int.max, ux1 = -1, uy1 = -1
for f in frames {
    if let b = bbox(f) { ux0 = min(ux0, b.minX); uy0 = min(uy0, b.minY); ux1 = max(ux1, b.maxX); uy1 = max(uy1, b.maxY) }
}
let pad = 4
let w0 = frames[0].w, h0 = frames[0].h
let crop = CGRect(x: max(0, ux0 - pad), y: max(0, uy0 - pad),
                  width: min(w0, ux1 + pad + 1) - max(0, ux0 - pad),
                  height: min(h0, uy1 + pad + 1) - max(0, uy0 - pad))
print("crop \(crop)")

// MARK: - Loop detection
// Shortest k whose frame matches frame 0 almost as well as the best match
// anywhere (multiples of the step cycle all score similarly).

let minLoop = 10
let diffs = (minLoop..<frames.count).map { (k: $0, d: diff(frames[0], frames[$0], crop)) }
let globalBest = diffs.map(\.d).min() ?? 0
let tolerance = globalBest * 1.15 + 0.05
let (bestK, bestD) = diffs.first(where: { $0.d <= tolerance }).map { ($0.k, $0.d) } ?? (frames.count, 0)
print("loop length \(bestK) frames (diff \(String(format: "%.2f", bestD)))")

// MARK: - Write

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for i in 0..<bestK {
    writePNG(frames[i], crop: crop, to: outDir.appendingPathComponent(String(format: "cat_%03d.png", i)))
}
print("wrote \(bestK) frames to \(outDir.path)")
