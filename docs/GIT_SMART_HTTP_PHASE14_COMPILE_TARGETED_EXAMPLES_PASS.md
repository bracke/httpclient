# Git smart HTTP Phase 14 compile-targeted examples pass

Phase 14 adds compile-targeted Git smart HTTP examples for external Ada consumers of `Http_Client`.
The examples are integration-surface documentation, not a downstream adapter. They do not add
`Version.Transport.Http`, Git object parsing, pkt-line parsing, or packfile parsing.

The examples are built by `examples/examples.gpr` and use reserved `.invalid` origins so the
release verification can compile them without contacting GitHub, GitLab, or any public remote.
Runnable end-to-end behavior remains covered by the deterministic local AUnit fixtures from earlier
phases.

## Compile-checked example coverage

The Phase 14 examples cover:

- `git_info_refs_streaming_get.adb` — HTTPS `info/refs` GET with binary streaming reads.
- `git_upload_pack_post_buffered.adb` — upload-pack POST with an explicit byte-array body.
- `git_receive_pack_fixed_upload.adb` — receive-pack fixed-length producer upload.
- `git_receive_pack_chunked_upload.adb` — receive-pack unknown-length producer upload; caller
  supplies entity bytes only and `Http_Client` owns HTTP/1.1 chunk framing.
- `git_chunked_upload_with_trailers.adb` — request trailers on an unknown-length chunked upload.
- `git_receive_pack_expect_continue.adb` — explicit `Expect: 100-continue` upload shape.
- `git_https_custom_ca.adb` — custom CA path while keeping TLS verification enabled.
- `git_https_proxy_connect.adb` — HTTPS origin routed through an explicit HTTP CONNECT proxy.
- `git_socks5_https.adb` — HTTPS origin routed through an explicit SOCKS5 proxy.
- `git_streaming_decompression.adb` — explicit streaming decompression opt-in.
- `git_http2_streaming_fetch_shape.adb` — explicit HTTP/2 streaming fetch shape.
- `http3_force_no_backend.adb` — forced HTTP/3 no-backend deterministic boundary.
- `git_redirect_policy.adb` — conservative redirect policy for Git discovery.
- `git_retry_policy.adb` — conservative retry policy for Git discovery.
- `git_streaming_with_timeout_and_cancellation.adb` — timeout and cancellation setup.
- `git_binary_safe_transport_shape.adb` — byte-array body handling with NUL and high bytes.

## Safety properties

The examples keep cookies disabled unless explicitly configured, keep decompression disabled except
in the decompression example, keep redirects and retries disabled unless the policy example enables
them, and do not disable TLS verification in positive HTTPS paths. Git request and response payloads
are represented as `Ada.Streams.Stream_Element_Array` at the public body boundary. Packet-line and
packfile bytes are not treated as text, decoded as UTF-8, normalized for line endings, stripped of
NUL bytes, or routed through string convenience response helpers.

## Verification command

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

The full Git smart HTTP release guard also checks that the Phase 14 examples are present, mentioned
in documentation, free of downstream adapter package names, free of unsafe TLS verification disable
in positive examples, and free of Git binary response-body string convenience usage.
