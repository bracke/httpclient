# Git smart HTTP Phase 12 redirect/retry safety pass

Phase 12 audits the final redirect and retry boundary for Git smart HTTP use.

## Frozen policy

Redirects are disabled by default. `Execute`, `Execute_Once`, and ordinary buffered execution return complete 3xx responses unchanged unless an explicit redirect-aware API is used with `Follow_Redirects => True`, or `Execute_Following_Redirects` is called deliberately.

Retries are disabled by default. `Default_Retry_Options.Enable_Retries` is `False`, and `Maximum_Attempts` defaults to one. Enabling retries remains an explicit caller decision.

HTTPS-to-HTTP redirects are blocked by default. `Allow_HTTPS_To_HTTP_Redirects` must be set explicitly before a downgrade is followed. TLS verification defaults are not weakened by redirect handling.

Cross-origin redirects strip caller-supplied `Authorization`, `Proxy-Authorization`, `Cookie`, `Cookie2`, and `Git-Protocol` headers by default. `Proxy-Authorization` remains proxy-scoped and is never converted into an origin credential.

Redirect method handling is conservative:

* `303` rewrites non-`HEAD` methods to `GET` and drops the body.
* `HEAD` remains `HEAD` through `303`.
* `301` and `302` use the configured `Method_Policy_301_302`; the default rewrites `POST` to `GET` and drops the body.
* `307` and `308` preserve method and body only when body replay is explicitly allowed and the body is replayable.
* Body-specific headers such as `Content-Type`, `Content-Encoding`, `Content-Language`, `Content-Location`, `Content-MD5`, `Digest`, and `Expect` are removed when redirect handling drops the body. A rewritten `GET` must not carry stale Git upload metadata or `Expect: 100-continue`.

Non-replayable request bodies are not retried and are not replayed across redirects. Buffered byte-array bodies are replayable and preserve exact `Ada.Streams.Stream_Element_Array` bytes. Streaming producers are replayable only when declared replayable and `Reset` succeeds.

Git push safety: `git-receive-pack` uploads should be modeled as non-replayable unless the caller can reset the producer to emit exactly identical bytes. A write failure, partial upload, timeout, or 307/308 redirect must not silently resend a non-replayable push body.

Protocol and proxy policy are preserved across redirect/retry chains. `Force_HTTP_1_1`, `Force_HTTP_2`, and `Force_HTTP_3` remain forced; retry or redirect handling never silently falls back to another protocol. Explicit HTTP proxy and SOCKS5 routes are reused for every attempt and are not bypassed.

Cancellation stops retry/redirect loops. It is not classified as a transient failure.

Cookies remain explicit and non-browser-like. Without a caller-supplied cookie jar, redirect and retry handling does not store or replay cookies. With a jar, cookie behavior follows the configured strict/merge policy and the normal origin scoping rules.

Diagnostics, when enabled, must redact credentials, cookies, bearer tokens, request bodies, and Git pack data.

## Phase 12 coverage markers

The AUnit and release guard coverage for this phase includes these explicit markers:

* Test_Client_Redirect_Disabled_Returns_302
* Test_Client_Redirect_Missing_Location_Is_Invalid
* Test_Client_Redirect_307_Body_Replay_Disallowed
* Test_Client_Redirect_303_Preserves_HEAD
* Test_Client_Redirect_303_Post_Drops_Body_Headers
* Test_Client_Redirect_308_Replays_Body_When_Allowed
* Test_Client_Cross_Origin_Redirect_Strips_Credentials
* Test_Client_Redirect_Max_Count
* Test_Client_Retry_Disabled_Remains_One_Attempt
* Test_Retry_Failure_Classification
* Test_Retry_Response_Status_Classification
* Test_Retry_Non_Retryable_Security_And_Protocol_Failures
* Test_Client_Retry_Post_503_Not_Retried_By_Default
* Test_Cancellation_Is_Not_Retryable
* Test_HTTP3_No_Backend_Not_Retried_As_HTTP1

## Verification

The intended verification gate is unchanged:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```

