/** Runtime bindings and request context used by the Cloudflare Worker entrypoint. */
type WorkerBindings = Record<string, any> & { DB?: any; STATUS?: any };
type WorkerContext = { waitUntil(promise: Promise<unknown>): void };

