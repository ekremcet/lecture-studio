import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
}

/// The app's replacement for sonner: a short stack of notices in the bottom-right corner.
@MainActor @Observable
final class ToastCenter {
    private(set) var toasts: [Toast] = []

    func show(_ kind: Toast.Kind, _ title: String, _ detail: String? = nil) {
        let t = Toast(kind: kind, title: title, detail: detail)
        toasts.append(t)
        if toasts.count > 4 { toasts.removeFirst() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((kind == .error ? 8 : 4) * 1_000_000_000))
            self?.dismiss(t.id)
        }
    }
    func success(_ title: String, _ detail: String? = nil) { show(.success, title, detail) }
    func error(_ title: String, _ error: Error) { show(.error, title, error.localizedDescription) }
    func error(_ title: String, _ detail: String? = nil) { show(.error, title, detail) }
    func dismiss(_ id: UUID) { toasts.removeAll { $0.id == id } }
}

struct ToastOverlay: View {
    let center: ToastCenter
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: t.kind == .success ? "checkmark.circle.fill" : t.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(t.kind == .success ? Color.green : t.kind == .error ? Color.red : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.callout.weight(.medium))
                        if let d = t.detail, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    }
                    Spacer(minLength: 0)
                    Button { center.dismiss(t.id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(width: 320, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.2), value: center.toasts)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}
