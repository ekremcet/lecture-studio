/** The two directions of the WKWebView bridge: fire-and-forget messages up to Swift, and replies. */

declare global {
  interface Window {
    webkit?: { messageHandlers: Record<string, { postMessage: (m: unknown) => Promise<unknown> | void }> };
  }
}

/** Send an event to Swift. Silently a no-op in a plain browser, which keeps the bundles testable. */
export function post(channel: string, message: unknown): void {
  try {
    void window.webkit?.messageHandlers[channel]?.postMessage(message);
  } catch (e) {
    console.warn("bridge post failed", channel, e);
  }
}

/** Ask Swift for something and wait for the answer (a WKScriptMessageHandlerWithReply). */
export async function ask<T = unknown>(channel: string, message: unknown): Promise<T> {
  const h = window.webkit?.messageHandlers[channel];
  if (!h) throw new Error(`no native handler for ${channel}`);
  return (await h.postMessage(message)) as T;
}

/** Errors have to cross the bridge as plain data. */
export function errorText(e: unknown): string {
  return String((e as Error)?.message ?? e);
}
