// Draws the background of the disk image window: a neutral ground, an arrow from the app to the
// Applications link, and one line of help. Usage: swift scripts/dmg-background.swift <out.png> [width height]
// (points; the file is rendered at 2x). Icon positions in package.sh assume 560 x 360.
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else { FileHandle.standardError.write(Data("usage: dmg-background.swift <out.png> [width height]\n".utf8)); exit(2) }
let out = URL(fileURLWithPath: args[1])
let width = args.count > 3 ? CGFloat(Double(args[2]) ?? 560) : 560
let height = args.count > 3 ? CGFloat(Double(args[3]) ?? 360) : 360
let scale: CGFloat = 2

let image = NSImage(size: NSSize(width: width, height: height))
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Ground: a quiet warm gray that reads in light and dark Finder windows alike.
NSColor(calibratedRed: 0.945, green: 0.945, blue: 0.95, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Arrow between the two icons (the icons sit at y = 170 from the top in Finder coordinates, 128 pt).
let y = height - 170
let path = NSBezierPath()
path.lineWidth = 6
path.lineCapStyle = .round
path.lineJoinStyle = .round
path.move(to: NSPoint(x: 232, y: y))
path.line(to: NSPoint(x: 328, y: y))
path.move(to: NSPoint(x: 306, y: y + 22))
path.line(to: NSPoint(x: 328, y: y))
path.line(to: NSPoint(x: 306, y: y - 22))
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
path.stroke()

// Help line under the icons.
let para = NSMutableParagraphStyle()
para.alignment = .center
let text = NSAttributedString(string: "Drag Lecture Studio into Applications, then open it from there.", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    // Mid gray: Finder dims background pictures in dark mode, and this still reads on the dimmed ground.
    .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1),
    .paragraphStyle: para,
])
text.draw(in: NSRect(x: 20, y: 64, width: width - 40, height: 24))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: out)
print("wrote \(out.path) \(Int(width))x\(Int(height))@\(Int(scale))x")
