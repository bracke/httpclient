# Phase 16 client ergonomic defaults documentation pass

This pass updates the documentation and examples after changing the high-level `Http_Client.Clients` default behavior before 1.0.

Documented behavior:

- `Default_Client_Configuration` follows bounded safe redirects by default.
- HTTPS-to-HTTP redirects remain blocked by default.
- Cross-origin credentials are stripped by default.
- `Default_Client_Configuration.Enable_Decompression` is enabled for buffered final responses.
- `Strict_Client_Configuration` preserves exact no-redirect/no-transform behavior.
- `Response_Text` is the ordinary caller-facing body helper.
- `Final_URL` exposes the printable post-redirect URL.
- The one-shot `Get (URL, Result, Configuration)` helper is the simple download entry point.

Git smart HTTP documentation continues to require exact byte preservation through streaming byte-array paths, `Accept-Encoding: identity`, or strict client configuration where buffered high-level configuration is used.
