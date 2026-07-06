# API overview

`http_client` exposes an explicit Ada 2022 API for building and executing HTTP requests without hidden browser policy. The ordinary stable entry point is `Http_Client.Clients`; lower-level stable packages remain available for callers that need deterministic URI parsing, request construction, header validation, response handling, transport configuration, streaming, uploads, caching, diagnostics, authentication, proxies, and protocol-specific controls.

## Stable surface

The stable public surface is listed in `PUBLIC_PACKAGES.md` and frozen in `RELEASE_SURFACE_MANIFEST.md`. Stable packages are intended to remain source-compatible after the 1.0 line begins. Applications may rely on documented package names, public type names, public record fields, public status values, and subprogram signatures in those packages.

## Experimental surface

`Http_Client.HTTP3`, `Http_Client.HTTP3.*`, and `Http_Client.QUIC` are release experimental APIs. They are visible so HTTP/3 configuration, QPACK/frame handling, fallback decisions, and backend boundaries are testable. They are not a promise of browser-equivalent networking, hidden QUIC backend selection, proxy bypass, 0-RTT, server push caching, MASQUE, CONNECT-UDP, or WebTransport.

## Internal surface

`Http_Client.Crypto`, `Http_Client.TLS`, test fixtures, generated helper data, persistent-cache byte layouts, encrypted-cache record layouts, and backend bridge details are implementation details unless a package specification explicitly states otherwise. Use the stable API rather than depending on file formats, diagnostic text, or private transport internals.


## High-level client convenience

`Http_Client.Clients.Get (URL, Result)` is the one-shot convenience path for ordinary downloads. It uses `Default_Client_Configuration`, which follows safe redirects and enables bounded final-response decompression. `Http_Client.Clients.Response_Text (Result)` returns the decoded response body when a decoded view exists, otherwise the final response body. `Http_Client.Clients.Final_URL (Result)` returns the printable URL reached after redirects. `Strict_Client_Configuration` disables automatic redirects and decompression for exact protocol callers.

The HTTP/2 HPACK decoder accepts both raw and RFC 7541 static-Huffman string literals for header names and values. Malformed Huffman payloads fail deterministically with `HPACK_Huffman_Error`; decoded strings are validated and inserted into the dynamic table only after successful decoding.

### Response metadata convenience accessors

Buffered responses returned by `Client.Get` and `Client.Execute` expose common response metadata directly through `Http_Client.Responses`. Callers can use `Has_Content_Type`, `Content_Type`, `Media_Type`, `Has_Charset`, and `Charset` instead of manually fetching and parsing `Content-Type` from the header list.

These helpers report server-declared HTTP metadata only. They do not sniff the response body, infer MIME types from URLs or file extensions, change buffering limits, or perform character-set conversion.

## IPv6 literal URLs

HTTP and HTTPS URLs may use IPv6 address literals in the standard bracketed authority form:

```ada
Status := Http_Client.Clients.Get
  ("http://[::1]:8080/",
   Result);
```

Support matrix:

| Host form | Status | Notes |
| --- | --- | --- |
| DNS hostnames | Supported | Normal DNS name parsing and TLS DNS-name verification apply. |
| IPv4 literals | Supported | TLS requires a matching IPv4 IP subjectAltName for HTTPS. |
| IPv6 literals | Supported in bracketed URI form, such as `http://[::1]/`. | Socket/TLS code receives the unbracketed address internally; emitted URI authorities and Host headers remain bracketed. |
| IPv6 zone identifiers | Unsupported | Scoped forms such as `http://[fe80::1%25lo0]/` fail deterministically. |
| h2c | Unsupported | Plain HTTP/2 cleartext upgrade remains out of scope. |

HTTPS to an IPv6 literal keeps certificate verification enabled. The certificate must contain a matching IPv6 IP subjectAltName; DNS-only certificates fail hostname/IP verification.

