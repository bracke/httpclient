# Stable API contract

This document is the compact release contract for application authors. `docs/RELEASE_SURFACE_MANIFEST.md` remains the package-by-package source of truth; this file records the declarations that should be protected by API-stability compile tests and compatibility review.

## Stable package names

Stable application packages: `Http_Client`, `Http_Client.URI`, `Http_Client.Types`, `Http_Client.Errors`, `Http_Client.Cancellation`, `Http_Client.Headers`, `Http_Client.Requests`, `Http_Client.Responses`, `Http_Client.Clients`, `Http_Client.Response_Streams`, `Http_Client.Request_Bodies`, `Http_Client.Multipart`, `Http_Client.Cookies`, `Http_Client.Decompression`, `Http_Client.Retry`, `Http_Client.Auth`, `Http_Client.Auth.Bearer`, `Http_Client.Auth.Digest`, `Http_Client.Auth.Scopes`, `Http_Client.Proxies`, `Http_Client.Proxies.SOCKS`, `Http_Client.Cache`, `Http_Client.Cache.Persistent`, `Http_Client.Diagnostics`, `Http_Client.TLS.Client_Certificates`, `Http_Client.Async`, `Http_Client.Alt_Svc`, `Http_Client.DNS_SVCB`, `Http_Client.HTTPS_Records`, `Http_Client.Protocol_Discovery`, `Http_Client.Proxy_Discovery`, and `Http_Client.Resources`.

Stable low-level packages: `Http_Client.HTTP1`, `Http_Client.HTTP1.Reader`, `Http_Client.Transports`, `Http_Client.Transports.TCP`, `Http_Client.Transports.TLS`, `Http_Client.Transports.SOCKS`, `Http_Client.Connection_Pools`, `Http_Client.HTTP2`, `Http_Client.HTTP2.Settings`, `Http_Client.HTTP2.Mapping`, `Http_Client.HTTP2.HPACK`, `Http_Client.HTTP2.Frames`, `Http_Client.HTTP2.Streams`, `Http_Client.HTTP2.Connection`, `Http_Client.HTTP2.Single_Stream`, `Http_Client.HTTP2.Body_Streams`, and `Http_Client.HTTP2.Uploads`. `Http_Client.HTTP2_Execution_Common` is a private implementation child package and is not part of the stable low-level API.

Experimental package names: `Http_Client.HTTP3`, `Http_Client.HTTP3.Execution`, `Http_Client.HTTP3.Frames`, `Http_Client.HTTP3.Mapping`, `Http_Client.HTTP3.QPACK`, `Http_Client.HTTP3.Settings`, `Http_Client.HTTP3.Streams`, `Http_Client.HTTP3.Body_Streams`, and `Http_Client.QUIC`. These are intentionally visible but not covered by the same source-compatibility promise.

Implementation-boundary package names: `Http_Client.Crypto`, `Http_Client.TLS`, and `Http_Client.Zlib_Decompression`. Do not depend on their internal representation unless a future release deliberately promotes a declaration.

## Stable core type names

The following public type names are release commitments when they appear in stable package specs: `URI_Reference`, `HTTP_Method`, `Status_Code`, `Result_Status`, `Result_Category`, `Cancellation_Token`, `Cancellation_Token_Access`, `Header_List`, `Request`, `Response`, `Client`, `Client_Configuration`, `Execution_Options`, `Redirect_Options`, `Streaming_Response`, `Streaming_Options`, `Request_Body`, `Multipart_Form`, `Cookie_Jar`, `Cookie_Limits`, `Decompression_Options`, `Retry_Options`, `Origin_Scope`, `Challenge`, `Proxy_Config`, `Cache_Config`, `Cache_Store`, `Persistent_Config`, `Persistent_Store`, `Encrypted_Persistent_Config`, `Encrypted_Persistent_Store`, `Diagnostics_Context`, `Redaction_Policy`, `Client_Certificate`, `Async_Configuration`, `Async_Client`, `Async_Handle`, `Pooling_Options`, `Pool_Key`, `Reader_Options`, `Timeout_Config`, `TLS_Options`, `HTTP2_Options`, `HTTP3_Options`, `Parse_Result`, `SVCB_Record`, `HTTPS_Record`, `Discovery_Options`, and `Discovery_Cache`.

Record fields in these stable records are source-compatibility commitments unless explicitly documented as experimental or implementation-only in the owning `.ads` file. Changing field names, field types, default values, ownership semantics, or security behavior is a breaking change after the compatibility promise begins.

## Stable result statuses

`Http_Client.Errors.Result_Status` values are program-control API. Current values are:

`Invalid_URI, Invalid_Header, Invalid_Request, Connection_Failed, DNS_Failed, Not_Connected, Write_Failed, Read_Failed, End_Of_Stream, Incomplete_Message, TLS_Failed, Certificate_Verification_Failed, Hostname_Verification_Failed, TLS_Handshake_Failed, CA_Store_Failed, TLS_Client_Certificate_Load_Failed, TLS_Client_Key_Load_Failed, TLS_Client_Key_Mismatch, TLS_Client_Key_Passphrase_Required, TLS_Client_Key_Passphrase_Invalid, TLS_Client_Certificate_Unsupported, TLS_Client_Certificate_Rejected, TLS_Client_Certificate_Scope_Mismatch, TLS_Client_Certificate_Configuration_Invalid, Timeout, Cancelled, Response_Too_Large, Integrity_Check_Failed, Header_Too_Large, Too_Many_Redirects, Invalid_Redirect, Invalid_Cookie, Cookie_Rejected, Cookie_Too_Large, Unsupported_Content_Encoding, Decompression_Failed, Decoded_Body_Too_Large, Invalid_Proxy, Proxy_Unsupported, Proxy_Connection_Failed, Proxy_Tunnel_Failed, Proxy_Authentication_Required, Invalid_SOCKS_Proxy, SOCKS_Unsupported_Version, SOCKS_Unsupported_Authentication_Method, SOCKS_Authentication_Failed, SOCKS_Connect_Failed, SOCKS_General_Server_Failure, SOCKS_Connection_Not_Allowed, SOCKS_TTL_Expired, SOCKS_Command_Unsupported, SOCKS_Malformed_Reply, SOCKS_Address_Type_Unsupported, SOCKS_Reply_Connection_Refused, SOCKS_Reply_Network_Unreachable, SOCKS_Reply_Host_Unreachable, Invalid_Credentials, Unsupported_Authentication_Scheme, Authentication_Required, Authentication_Failed, Authentication_Replay_Disallowed, Authentication_Challenge_Malformed, Authentication_Scope_Mismatch, Digest_Algorithm_Unsupported, Digest_QOP_Unsupported, Digest_Nonce_Stale, Authentication_Loop_Detected, Invalid_Configuration, Client_Not_Initialized, Retry_Disallowed, Retry_Body_Not_Replayable, Body_Not_Replayable, Body_Length_Mismatch, Body_Producer_Failed, Upload_Too_Large, Chunked_Upload_Unsupported, Invalid_Multipart_Boundary, Invalid_Form_Field, Invalid_File_Name, Multipart_Too_Large, Too_Many_Parts, Part_Length_Unknown, Part_Producer_Failed, Cache_Miss, Cache_Entry_Stale, Cache_Revalidation_Failed, Cache_Entry_Too_Large, Cache_Disabled, Invalid_Cache_Metadata, Cache_Open_Failed, Cache_Read_Failed, Cache_Write_Failed, Cache_Corrupt_Entry, Cache_Format_Unsupported, Cache_Limit_Exceeded, Cache_Storage_Unavailable, Cache_Encryption_Failed, Cache_Decryption_Failed, Cache_Authentication_Failed, Cache_Key_Invalid, Cache_KDF_Failed, Cache_Random_Failed, Cache_Encrypted_Format_Unsupported, Cache_Wrong_Key, HTTP2_Protocol_Error, HTTP2_Frame_Error, HTTP2_Compression_Error, HTTP2_Flow_Control_Error, HTTP2_Settings_Error, HTTP2_Header_Error, HTTP2_Stream_Reset, HTTP2_Stream_Refused, HTTP2_Stream_Limit_Reached, HTTP2_Stream_State_Error, HTTP2_Connection_Goaway, HTTP2_Header_Block_Interleaving_Error, HTTP2_Multiplexing_Unsupported, HTTP2_Unsupported_Feature, HTTP3_Unsupported, HTTP3_Frame_Error, HTTP3_Settings_Error, HTTP3_QPACK_Error, HTTP3_Stream_Error, HTTP3_Goaway, HTTP3_Protocol_Error, QUIC_Unsupported, QUIC_Connection_Failed, QUIC_Handshake_Failed, QUIC_Transport_Error, HTTP3_Proxy_Unsupported, HTTP3_Fallback_Disallowed, ALPN_Negotiation_Failed, HPACK_Decode_Failed, HPACK_Huffman_Error, Pool_Closed, Pool_Exhausted, Connection_Not_Reusable, Stale_Connection, Redirect_Downgrade_Blocked, Redirect_Body_Replay_Disallowed, Protocol_Error, Unsupported_Feature, Async_Queue_Full, Async_Cancelled, Async_Shutdown, Async_Not_Ready, Async_Result_Already_Taken, Async_Handle_Invalid, Async_Worker_Failed, Async_Unsupported_Mode, Internal_Error`.

Status text and diagnostics strings are not program-control API. `Http_Client.Errors.Category` is the stable coarse grouping helper for logging, metrics, and coarse recovery.

## Stable option/default objects

The following defaults are stable names and should be kept synchronized with documentation and API-stability compile tests: `Default_Client_Configuration`, `Strict_Client_Configuration`, `Default_Execution_Options`, `Default_Redirect_Options`, `Strict_Redirect_Options`, `Default_TLS_Options`, `Default_Retry_Options`, `Default_Cache_Config`, `Default_Enabled_Cache_Config`, `Default_Decompression_Options`, `Default_Streaming_Options`, `Default_Async_Configuration`, `Default_Pooling_Options`, `Default_HTTP2_Options`, `Default_HTTP3_Options`, `Default_Discovery_Options`, `Default_Discovery_Policy`, `Default_Reader_Options`, `Default_Timeouts`, `Default_Limits`, and persistent-cache `Make_Config` / `Make_Encrypted_Config` construction helpers.

## Representative stable subprogram signatures

The API-stability compile test must continue to import and type-check representative calls to `Http_Client.URI.Parse`, URI host validation and classification helpers, `Http_Client.Headers.Add`, `Http_Client.Requests.Create`, authentication header helpers, `Http_Client.Clients.Create`, `Http_Client.Clients.Validate`, `Http_Client.Clients.Get` and `Http_Client.Clients.Head` one-shot and client-bound forms, `Http_Client.Clients.Response_Text`, `Http_Client.Clients.Final_URL`, response metadata helpers such as `Http_Client.Responses.Content_Type`, `Media_Type`, and `Charset`, `Http_Client.Clients.Execute` shapes where practical, `Http_Client.Cache.Initialize`, `Http_Client.Cache.Persistent.Open`/`Close`, `Http_Client.Diagnostics.Initialize`, `Http_Client.Proxies.Parse`, SOCKS helpers, `Http_Client.Connection_Pools.Key_For`, `Http_Client.Request_Bodies.From_String`, multipart construction helpers, `Http_Client.HTTP2` configuration, experimental `Http_Client.HTTP3.Execution_Status`, Alt-Svc/HTTPS/SVCB parsers, protocol-discovery validation, client-certificate validation, `Http_Client.Cancellation.Cancel`/`Reset`/`Is_Cancelled`, and `Http_Client.Errors.Category`.

A release is incomplete if a stable declaration is removed, renamed, or narrowed without either updating this document as a deliberate breaking correction reviewed for a major-version boundary or marking the declaration deprecated with a replacement and compatibility window.

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

