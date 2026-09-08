// Crops a generated icon to the squircle the model drew (dropping the white margin around it), scales it
// to the full canvas and clips it to the macOS icon shape so the corners are transparent.
import AppKit
let args = CommandLine.arguments
guard args.count == 3, let img = NSImage(contentsOfFile: args[1]), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let w = cg.width, h = cg.height
// Read pixels to find the bounding box of everything that is not near-white.
let probe = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
probe.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = probe.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4
    if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) < 3 * 235 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
} }
var box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
// Keep it square around the centre, and ignore a crop that would be tiny (a mostly white image).
let side = max(box.width, box.height)
if side > CGFloat(w) * 0.5 { box = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side) } else { box = CGRect(x: 0, y: 0, width: w, height: h) }
let cropped = cg.cropping(to: box.intersection(CGRect(x: 0, y: 0, width: w, height: h)))!
let size = CGSize(width: 1024, height: 1024)
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
// Apple's icon grid: the rounded square spans the full canvas with a corner radius of about 22.4 %.
let path = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: size.width * 0.2237, cornerHeight: size.height * 0.2237, transform: nil)
ctx.addPath(path); ctx.clip()
ctx.draw(cropped, in: CGRect(origin: .zero, size: size))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
