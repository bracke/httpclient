with Http_Client.Errors;
with Http_Client.Responses;
with Http_Client.Requests;
with Http_Client.Types;

package Http_Client.Retry is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit bounded retry policy helpers.
   --
   --  This package contains retry classification and delay calculation only. It
   --  performs no network I/O, sleeps, redirects, cookie handling,
   --  decompression, proxy routing, HTTP/2, HPACK, caching, connection pooling,
   --  authentication workflow, circuit breaking, or browser-like behavior.

   subtype Delay_Milliseconds is Natural;
   --  Retry delay expressed in milliseconds.

   type Backoff_Mode is
     (Fixed_Delay,
      Exponential_Delay);
   --  Deterministic retry backoff mode.
   --
   --  Fixed_Delay returns Base_Delay for every retry. Exponential_Delay doubles
   --  the previous delay for each later retry, capped by Maximum_Delay.

   type Delay_Hook_Access is access procedure
     (Pause : Delay_Milliseconds);
   --  Optional hook invoked before a retry attempt.
   --
   --  Production callers may supply a procedure that sleeps. Tests may supply a
   --  procedure that records planned delays. A null hook means no wall-clock
   --  sleep is performed by the retry layer. Retry-aware client APIs catch hook
   --  exceptions and convert them to Internal_Error rather than allowing them to
   --  escape the public API.

   type Retry_Options is record
      Enable_Retries              : Boolean := False;
      Maximum_Attempts            : Positive := 1;
      Retry_Connect_Failures      : Boolean := True;
      Retry_Read_Failures         : Boolean := True;
      Retry_Write_Failures        : Boolean := True;
      Retry_Timeouts              : Boolean := True;
      Retry_5xx_Responses         : Boolean := False;
      Retry_429                   : Boolean := False;
      Retry_425                   : Boolean := False;
      Retry_408                   : Boolean := False;
      Base_Delay                  : Delay_Milliseconds := 0;
      Maximum_Delay               : Delay_Milliseconds := 0;
      Backoff                     : Backoff_Mode := Fixed_Delay;
      Respect_Retry_After         : Boolean := False;
      Maximum_Retry_After         : Delay_Milliseconds := 60_000;
      Allow_Non_Idempotent_Retry  : Boolean := False;
      Retry_Transient_TLS_Failure : Boolean := False;
      Delay_Hook                  : Delay_Hook_Access := null;
   end record;
   --  Explicit retry policy.
   --
   --  @field Enable_Retries False preserves single-attempt behavior.
   --  @field Maximum_Attempts Total attempts including the first one.
   --  @field Retry_Connect_Failures Retry transient DNS/connect/proxy-open
   --         failures when method and body replay rules permit.
   --  @field Retry_Read_Failures Retry incomplete reads, premature close, and
   --         incomplete response framing when method and replay rules permit.
   --  @field Retry_Write_Failures Retry write failures only under the method
   --         policy. The transport may not prove whether bytes reached the
   --         server, so non-idempotent methods remain disabled by default.
   --  @field Retry_Timeouts Retry timeout statuses when method and replay rules
   --         permit.
   --  @field Retry_5xx_Responses Retry 500, 502, 503, and 504 complete HTTP
   --         responses when enabled.
   --  @field Retry_429 Retry 429 complete HTTP responses when enabled.
   --  @field Retry_425 Retry 425 complete HTTP responses when enabled.
   --  @field Retry_408 Retry 408 complete HTTP responses when enabled.
   --  @field Base_Delay Pause before the first retry attempt.
   --  @field Maximum_Delay Cap applied to fixed, exponential, and Retry-After
   --         delays. Zero means no ordinary backoff delay.
   --  @field Backoff Fixed or exponential deterministic delay calculation.
   --  @field Respect_Retry_After Whether to honor conservative decimal
   --         delta-seconds Retry-After response headers. Whitespace, negative
   --         values, and HTTP-date values are rejected.
   --  @field Maximum_Retry_After Separate cap for Retry-After before the
   --         Maximum_Delay cap is also applied. Zero means no separate
   --         Retry-After cap.
   --  @field Allow_Non_Idempotent_Retry Explicitly allows POST and PATCH retry.
   --         Enabling this can duplicate application-level side effects.
   --  @field Retry_Transient_TLS_Failure Allows retry of TLS_Failed and
   --         TLS_Handshake_Failed. Certificate, hostname, and CA-store failures
   --         are never classified as retryable by default helpers.
   --  @field Delay_Hook Optional deterministic delay callback. Null performs no
   --         sleep and keeps unit tests fast.

   Default_Retry_Options : constant Retry_Options :=
     (Enable_Retries              => False,
      Maximum_Attempts            => 1,
      Retry_Connect_Failures      => True,
      Retry_Read_Failures         => True,
      Retry_Write_Failures        => True,
      Retry_Timeouts              => True,
      Retry_5xx_Responses         => False,
      Retry_429                   => False,
      Retry_425                   => False,
      Retry_408                   => False,
      Base_Delay                  => 0,
      Maximum_Delay               => 0,
      Backoff                     => Fixed_Delay,
      Respect_Retry_After         => False,
      Maximum_Retry_After         => 60_000,
      Allow_Non_Idempotent_Retry  => False,
      Retry_Transient_TLS_Failure => False,
      Delay_Hook                  => null);
   --  Conservative default: retries disabled.

   type Retry_Result is record
      Final_Response    : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Final_Status      : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Internal_Error;
      Attempts          : Positive := 1;
      Retries_Exhausted : Boolean := False;
      Last_Failure      : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Ok;
   end record;
   --  Metadata returned by retry-aware execution.
   --
   --  @field Final_Response Final parsed response. When retry exhaustion ends
   --         with a complete HTTP response such as 503, this response is
   --         preserved for caller inspection.
   --  @field Final_Status Final operation status. Complete HTTP responses use
   --         Ok even when their status code was retryable.
   --  @field Attempts Number of attempts actually made.
   --  @field Retries_Exhausted True when a retryable outcome was returned only
   --         because Maximum_Attempts stopped further attempts.
   --  @field Last_Failure Last non-Ok operation status observed, or Ok when the
   --         final outcome was a complete HTTP response.

   function Is_Retryable_Method
     (Method  : Http_Client.Types.Method_Name;
      Options : Retry_Options := Default_Retry_Options) return Boolean;
   --  GNATdoc contract.
   --  @param Method Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Method is allowed by the retry method policy.

   function Is_Request_Body_Replayable
     (Request : Http_Client.Requests.Request) return Boolean;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Request can be serialized identically for another attempt.
   --
   --  Empty and buffered request bodies are replayable. Fixed-length streaming
   --  request bodies are replayable only when their producer declares replay
   --  support and Reset can restore the initial byte position. One-shot
   --  streaming producers are rejected before retrying.

   function Is_Retryable_Response
     (Response : Http_Client.Responses.Response;
      Options  : Retry_Options := Default_Retry_Options) return Boolean;
   --  GNATdoc contract.
   --  @param Response Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Response status is enabled for response-status retry.

   function Is_Retryable_Status_Code
     (Status  : Http_Client.Types.Status_Code;
      Options : Retry_Options := Default_Retry_Options) return Boolean;
   --  GNATdoc contract.
   --  @param Status Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Status is enabled for response-status retry.

   function Is_Retryable_Failure
     (Status  : Http_Client.Errors.Result_Status;
      Options : Retry_Options := Default_Retry_Options) return Boolean;
   --  GNATdoc contract.
   --  @param Status Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Status is a transient failure enabled by Options.

   function Delay_For_Attempt
     (Attempt : Positive;
      Options : Retry_Options := Default_Retry_Options) return Delay_Milliseconds;
   --  GNATdoc contract.
   --  @param Attempt Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return the bounded delay before retrying after Attempt.
   --
   --  Attempt is the attempt number that just completed. For example, passing 1
   --  calculates the delay before attempt 2.

   function Retry_After_Delay
     (Value   : String;
      Options : Retry_Options := Default_Retry_Options;
      Pause   : out Delay_Milliseconds) return Boolean;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Pause Subprogram parameter.
   --  Parse Retry-After delta-seconds conservatively.
   --
   --  @return True when Value is a non-negative decimal delta-seconds value with
   --          no whitespace or sign. The value is converted to milliseconds,
   --          saturated on decimal accumulation or millisecond overflow, and
   --          capped by Options. HTTP-date Retry-After values are intentionally unsupported in this
   --          release and therefore return False deterministically.

end Http_Client.Retry;
