# Git smart HTTP HTTP/1.1 protocol-policy pass

This pass adds an explicit high-level protocol guard for consumers that require
HTTP/1.1 semantics.

## Public API

`Http_Client.Clients.Execution_Options` now contains:

```ada
Protocol_Policy : Protocol_Selection_Policy := Protocol_From_Configuration;
```

The policy values are:

```ada
type Protocol_Selection_Policy is
  (Protocol_From_Configuration,
   Force_HTTP_1_1);
```

`Protocol_From_Configuration` preserves the configured experimental HTTP/3 and
protocol-discovery behavior. `Force_HTTP_1_1` disables high-level HTTP/3
candidate execution and Alt-Svc/HTTPS-SVCB upgrade selection for that execution
path. The request is executed through the existing HTTP/1.1 TCP/TLS transport,
including proxy tunneling, streaming upload/download, chunked transfer decoding,
optional streaming decompression, redirects, retries, cookies, and TLS
verification according to the other explicit options.

`Http_Client.Response_Streams.Streaming_Options` now also contains an explicit
streaming protocol guard:

```ada
Protocol_Policy : Streaming_Protocol_Policy := Streaming_HTTP_1_1_Only;
```

The streaming response API now defaults to HTTP/1.1-only through `Streaming_HTTP_1_1_Only`. HTTP/2 and HTTP/3 streaming require explicit protocol-policy values and are never attempted implicitly through Alt-Svc or HTTPS/SVCB discovery.

## Git smart HTTP recommendation

Git smart HTTP integrations should set:

```ada
Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
```

and use `Http_Client.Response_Streams.Open` for response streaming. This prevents
an enabled client-wide HTTP/3 or discovery configuration from changing the
transport semantics used by Git pkt-line and packfile streaming.

## Compatibility

The default high-level policy is `Protocol_From_Configuration`, preserving
existing behavior for callers that intentionally configure experimental HTTP/3 or
discovery. The new field is explicit so Git integrations can force HTTP/1.1
without mutating the client-wide HTTP3 or Discovery configuration.
