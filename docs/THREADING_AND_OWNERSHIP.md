# Ownership, lifetime, and task-safety

Ownership is explicit. Ordinary mutable values are single-owner unless the package specification says otherwise.

- Requests, responses, header lists, cookie jars, caches, multipart forms, diagnostics contexts, and request-body producers are mutable values and are not task-safe by default.
- High-level `Client` values store reusable configuration. Sharing one mutable client across tasks requires external synchronization unless it is wrapped by `Http_Client.Async`.
- `Async_Client` owns its worker tasks and queue. `Shutdown` is idempotent and should be called explicitly before finalization.
- Streaming response objects own their live transport stream. The caller must read to end-of-body or call `Close`; early close discards reuse eligibility.
- Request-body producer access values are caller-owned. The library does not free producer objects and does not extend producer lifetime.
- Multipart request bodies borrow the form object used as producer. The form must stay alive and unmodified while upload execution is using it.
- Cache stores and persistent-cache handles are caller-owned. They must outlive client configurations that reference them.
- TLS client-certificate credentials are caller-owned values copied into TLS options; they do not imply any HTTP authorization scope.
- Proxy and SOCKS credentials are scoped to the configured proxy protocol only.

Close/finalization operations should be deterministic and idempotent. Calling close on an unopened backend connection or already closed stream should not produce a secondary failure. Resource-owning APIs should document whether finalization is a safety net or the primary cleanup mechanism; explicit close/shutdown remains preferred.
