import Foundation
import AppKit
import WebKit

/// Development aid: `STUDIO_SMOKE_ZOOM=1` (with `STUDIO_SMOKE`) checks the presenter's pinch zoom. A real
/// pinch cannot be synthesised, so this drives the same zoom the gesture does and reads the slide back
/// from the page: the point under the fingers must stay put, both slide views must show the same part
/// of the slide, the view must stay on the slide, and a new slide or Escape must zoom back out.
extension Smoke {
    static func zoomCheck(_ pres: Presentation, to dir: URL, note: (String) -> Void) async {
        func rect(_ c: PreviewController) async -> CGRect? {
            let js = "const s = Array.from(document.querySelectorAll('svg[data-marpit-svg]')).find(x => x.style.display !== 'none'); if (!s) return null; const r = s.getBoundingClientRect(); return [r.x, r.y, r.width, r.height, document.getElementById('deck').style.transform.length]"
            guard let a = try? await c.webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) as? [NSNumber], a.count == 5 else { return nil }
            return CGRect(x: a[0].doubleValue, y: a[1].doubleValue, width: a[2].doubleValue, height: a[3].doubleValue)
        }
        func shot(_ c: PreviewController, _ name: String) async {
            if let img = try? await c.webView.takeSnapshot(configuration: nil), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: dir.appendingPathComponent(name)) }
        }
        /// The slide point (0…1) in the middle of the view: the same on both views when they mirror.
        func middle(_ c: PreviewController) async -> String {
            guard let r = await rect(c) else { return "-" }
            let v = c.webView.bounds.size
            return String(format: "(%.3f, %.3f)", (v.width / 2 - r.minX) / r.width, (v.height / 2 - r.minY) / r.height)
        }
        func f(_ r: CGRect?) -> String { r.map { String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "-" }
        func pinch(_ label: String, on c: PreviewController, by factor: CGFloat, at p: CGPoint) async {
            guard let before = await rect(c) else { note("zoom \(label): no slide"); return }
            let u = CGPoint(x: (p.x - before.minX) / before.width, y: (p.y - before.minY) / before.height)
            pres.zoomSlide(by: factor, at: p, on: c)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let after = await rect(c) else { note("zoom \(label): no slide after"); return }
            let at = CGPoint(x: after.minX + u.x * after.width, y: after.minY + u.y * after.height)
            note(String(format: "zoom %@: scale=%.2f drift=%.1f pt view=%.0fx%.0f slide %@ -> %@", label, pres.zoom.scale, hypot(at.x - p.x, at.y - p.y), c.webView.bounds.width, c.webView.bounds.height, f(before), f(after)))
            note("  middle: show=\(await middle(pres.show)) current=\(await middle(pres.current)) model=\(String(format: "(%.3f, %.3f)", pres.zoom.center.x, pres.zoom.center.y))")
        }
        let show = pres.show, cur = pres.current
        let sv = show.webView.bounds.size, cv = cur.webView.bounds.size
        note("zoom: aspect=\(String(format: "%.3f", pres.slideAspect)) show=\(sv) current=\(cv) unzoomed show \(f(await rect(show))) current \(f(await rect(cur)))")
        await shot(show, "zoom-0-show.png")
        await pinch("show 2.5x", on: show, by: 2.5, at: CGPoint(x: sv.width * 0.3, y: sv.height * 0.35))
        await shot(show, "zoom-1-show.png")
        await shot(cur, "zoom-1-current.png")
        pres.panSlide(by: CGSize(width: -120, height: -80), on: show)
        try? await Task.sleep(nanoseconds: 400_000_000)
        note("pan -120,-80 on show: model=\(String(format: "(%.3f, %.3f)", pres.zoom.center.x, pres.zoom.center.y)) show=\(await middle(show)) current=\(await middle(cur))")
        await pinch("current 1.6x", on: cur, by: 1.6, at: CGPoint(x: cv.width * 0.7, y: cv.height * 0.6))
        await shot(cur, "zoom-2-current.png")
        await shot(show, "zoom-2-show.png")
        // Toward a corner: the slide's own corner stays at the view's corner on any axis the slide fills.
        pres.panSlide(by: CGSize(width: 5000, height: 5000), on: show)
        try? await Task.sleep(nanoseconds: 400_000_000)
        note("pan to the top-left corner: show \(f(await rect(show))) current \(f(await rect(cur)))")
        await shot(show, "zoom-3-corner-show.png")
        pres.zoomSlide(by: 0.01, at: CGPoint(x: sv.width / 2, y: sv.height / 2), on: show)
        try? await Task.sleep(nanoseconds: 400_000_000)
        note("pinched all the way out: zoomed=\(pres.zoom.isZoomed) show \(f(await rect(show)))")
        pres.zoomSlide(by: 3, at: CGPoint(x: sv.width / 2, y: sv.height / 2), on: show)
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let w = show.webView.window {
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        note("escape while zoomed: presenting=\(pres.presenting) zoomed=\(pres.zoom.isZoomed) show \(f(await rect(show)))")
        pres.zoomSlide(by: 3, at: CGPoint(x: sv.width / 2, y: sv.height / 2), on: show)
        try? await Task.sleep(nanoseconds: 300_000_000)
        if pres.index + 1 < pres.count { pres.next() } else { pres.previous() }
        try? await Task.sleep(nanoseconds: 600_000_000)
        note("new slide: index=\(pres.index) zoomed=\(pres.zoom.isZoomed) show \(f(await rect(show))) current \(f(await rect(cur)))")
        await shot(show, "zoom-4-next-show.png")
    }
}
