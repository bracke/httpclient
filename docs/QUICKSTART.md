# Quickstart

This quickstart is the shortest path from a fresh checkout to a small, explicit `http_client` program. It avoids optional live-network validation and advanced features so new users can build confidence before enabling redirects, retries, cookies, caches, proxies, diagnostics, async, HTTP/2, or experimental HTTP/3.

## 1. Build the crate

From the repository root:

```sh
alr build
```

Equivalent direct GPRbuild command:

```sh
alr exec -- gprbuild -P httpclient.gpr
```

`http_client` is an Ada 2022 library crate. HTTPS support uses OpenSSL-backed TLS support as documented by the crate metadata and project files.

## 2. Run the default offline tests

The default AUnit suite is deterministic and does not require public internet access:

```sh
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
```

Optional release checks are implemented as Ada tools:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
```

Coverage enforcement is a separate release-maintainer gate:

```sh
cd tests && alr exec -- ../tools/bin/run_aunit_coverage
```

## 3. Compile the examples

The examples are compile-oriented API examples. They are intentionally small and avoid real credentials:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

Useful first files:

- `examples/src/simple_get.adb`
- `examples/src/manual_request.adb`
- `examples/src/redirect_client.adb`
- `examples/src/http_proxy_config.adb`
- `examples/src/diagnostics_observer.adb`
- `examples/src/cache_config.adb`
- `examples/src/enable_http2.adb`
- `examples/src/enable_http3_experimental.adb`

## 4. First high-level GET

Use the one-shot `Http_Client.Clients.Get` helper for the simplest downloads:

```ada
with Ada.Text_IO;

with Http_Client.Clients;
with Http_Client.Errors;

procedure Simple_Get is
   use type Http_Client.Errors.Result_Status;

   Result : Http_Client.Clients.Client_Result;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Clients.Get ("https://example.com/", Result);

   if Status = Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line (Http_Client.Clients.Response_Text (Result));
   else
      --  Use Status for program control. Diagnostic text is for humans only.
      null;
   end if;
end Simple_Get;
```

Default high-level behavior is web-client friendly but still bounded: TLS certificate and hostname verification are enabled, safe redirects are followed, HTTPS-to-HTTP downgrade redirects are blocked, cross-origin credentials are stripped, bounded response decompression is enabled, retries are disabled, cookies are disabled unless a jar is supplied, caches are disabled, proxies are disabled, diagnostics are silent, async execution is explicit, and HTTP/3 is disabled unless configured.

Use `Strict_Client_Configuration` when a caller needs exact no-redirect/no-transform behavior:

```ada
Status := Http_Client.Clients.Get
  (URL           => "https://example.com/",
   Result        => Result,
   Configuration => Http_Client.Clients.Strict_Client_Configuration);
```

## 5. Manual request construction

Use the lower-level request model when application code needs to validate or assemble requests explicitly before execution:

```ada
with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Manual_Request is
   use type Http_Client.Errors.Result_Status;

   URI     : Http_Client.URI.URI_Reference;
   Request : Http_Client.Requests.Request;
   Status  : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.URI.Parse ("http://example.com/index.html", URI);

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Http_Client.Types.GET, URI, Request);
   end if;

   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Manual_Request;
```

## 6. Adjust one behavior at a time

Most non-trivial behavior is opt-in and bounded. Redirects and buffered decompression are already enabled by the high-level default, so this section shows how to customize redirect limits or choose strict behavior. Validate configuration after changing options:

```ada
with Http_Client.Clients;
with Http_Client.Errors;

procedure Redirect_Client is
   use type Http_Client.Errors.Result_Status;

   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Status : Http_Client.Errors.Result_Status;
begin
   Config.Redirects.Max_Redirects := 3;
   Config.Redirects.Allow_HTTPS_To_HTTP_Redirects := False;
   Config.Redirects.Strip_Credentials_Cross_Origin := True;

   Status := Http_Client.Clients.Validate (Config);
   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Redirect_Client;
```

The same pattern applies to retries, cookies, caches, proxies, diagnostics, async, HTTP/2, and experimental HTTP/3: start from the default configuration, enable the specific behavior deliberately, set limits, and call validation. For exact byte-preserving transport behavior, start from `Strict_Client_Configuration` instead.

## 7. Common next steps

Read these documents next:

- `docs/api-overview.md` for stable, experimental, and internal package boundaries.
- `docs/configuration.md` for the full configuration model.
- `docs/security.md` and `docs/SECURITY_MODEL.md` for security defaults and non-goals.
- `docs/DEFAULT_LIMITS.md` for concrete resource limits.
- `docs/TESTING.md` and `docs/AUNIT_SUITE.md` for the test model.
- `docs/EXAMPLES.md` for the example inventory.

## 8. Important non-goals

This crate is not a browser networking stack. It does not provide PAC/WPAD/browser proxy discovery, browser cache/profile integration, service workers, browser preload behavior, OAuth/OIDC/SAML token acquisition, NTLM/Negotiate/Kerberos, OS credential-store integration, password-manager integration, SOCKS UDP ASSOCIATE/BIND, MASQUE, CONNECT-UDP, WebTransport, 0-RTT, or browser-like automatic login behavior.

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

