with Ada.Finalization;

with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Requests;

package Http_Client.Async is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit bounded task integration for buffered high-level client requests.
   --
   --  This package is opt-in. Constructing ordinary Http_Client.Clients.Client
   --  values and using synchronous APIs creates no worker tasks, no global task
   --  pool, no hidden scheduler, and no event loop. An Async_Client owns its
   --  worker tasks and bounded FIFO queue. The async layer executes the existing
   --  synchronous buffered client pipeline inside worker tasks; it does not add
   --  nonblocking socket I/O or a browser-style networking loop.
   --
   --  Streaming responses are intentionally unsupported here. Submit accepts
   --  complete buffered requests and returns a handle whose result is a normal
   --  Http_Client.Clients.Client_Result. Upload body producers attached to a
   --  request are invoked from worker tasks; callers must only submit producers
   --  whose lifetime and task-safety are valid for that execution context.
   --
   --  The initial implementation serializes calls into the high-level pipeline
   --  inside each Async_Client. That conservative policy protects mutable client
   --  configuration, cookie jars, cache stores, persistent/encrypted cache
   --  handles, diagnostics contexts, authentication state, connection-pool
   --  metadata, and HTTP/2 connection state from unsynchronized concurrent
   --  mutation. Requests may still be submitted, queued, cancelled, waited on,
   --  and consumed without blocking the caller task on network I/O. When the
   --  wrapped client carries an enabled diagnostics context, this package emits
   --  structural async lifecycle events only; it does not copy headers, bodies,
   --  cookies, credentials, SOCKS credentials, client-certificate material,
   --  cache contents, or authentication secrets into those events.

   type Async_Client is new Ada.Finalization.Limited_Controlled with private;
   --  Caller-owned async client and task pool.
   --
   --  Initialize starts exactly Max_Workers worker tasks. Shutdown stops them
   --  deterministically. Finalization requests immediate shutdown as a cleanup
   --  safety net; callers should still call Shutdown explicitly to document the
   --  desired policy.

   type Request_Handle is private;
   --  Handle for one submitted buffered request.
   --
   --  A valid handle can be polled, waited on, cancelled, and consumed. Result
   --  consumes the stored Client_Result exactly once. Poll and Wait do not
   --  consume it. Dropping a handle does not cancel an in-flight operation;
   --  cancellation is explicit and best-effort.

   type Async_Configuration is record
      Max_Workers       : Positive := 2;
      Max_Queued        : Positive := 16;
      Cancel_On_Finalize : Boolean := True;
   end record;
   --  Bounded task-pool configuration.
   --
   --  @field Max_Workers Maximum number of worker tasks owned by the async
   --         client. No request creates an additional unbounded task.
   --  @field Max_Queued Maximum number of requests waiting in the FIFO queue.
   --  @field Cancel_On_Finalize When True, finalization requests immediate
   --         cancellation of queued work before stopping workers.

   Default_Async_Configuration : constant Async_Configuration :=
     (Max_Workers => 2,
      Max_Queued => 16,
      Cancel_On_Finalize => True);

   function Initialize
     (Item          : in out Async_Client;
      Client        : Http_Client.Clients.Client;
      Configuration : Async_Configuration := Default_Async_Configuration)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Client Subprogram parameter.
   --  @param Configuration Subprogram parameter.
   --  Start Item's bounded worker pool around a configured synchronous client.
   --
   --  @return Ok on success, Client_Not_Initialized if Client is not ready, or
   --          Invalid_Configuration if Item is already initialized.

   function Is_Initialized (Item : Async_Client) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True while Item owns a running or shutting-down pool.

   function Submit
     (Item    : in out Async_Client;
      Request : Http_Client.Requests.Request;
      Handle  : out Request_Handle) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Handle Subprogram parameter.
   --  Copy Request into the bounded FIFO queue and return a request handle.
   --
   --  @return Ok when queued, Async_Queue_Full when the queue is full,
   --          Async_Shutdown after shutdown has started or completed,
   --          Invalid_Request for an invalid request, or
   --          Client_Not_Initialized for an async client that has never been
   --          initialized.

   function Submit_Get
     (Item   : in out Async_Client;
      URL    : String;
      Handle : out Request_Handle) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @param Handle Subprogram parameter.
   --  @return Subprogram result.
   --  Parse URL, build a GET request, and submit it.

   function Poll
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Handle Subprogram parameter.
   --  @return Subprogram result.
   --  Return Async_Not_Ready until the operation completes. Once completed,
   --  return the operation status stored in the result. Invalid handles return
   --  Async_Handle_Invalid.

   function Wait
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Handle Subprogram parameter.
   --  @return Subprogram result.
   --  Block the caller until Handle completes, then return the operation status.
   --  Waiting does not consume the result.

   function Cancel
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Handle Subprogram parameter.
   --  @return Subprogram result.
   --  Request best-effort cancellation.
   --
   --  Pending queued requests complete as Async_Cancelled and do not start.
   --  In-flight requests observe cancellation only at synchronous pipeline
   --  boundaries and timeout/connection-close points. Immediate interruption of
   --  blocking DNS, socket, TLS, SOCKS, proxy, HTTP/2, upload, or response reads
   --  is not promised. Cancelling a handle that has already completed returns
   --  the completed operation status and does not rewrite the stored result.

   function Result
     (Handle : Request_Handle;
      Value  : out Http_Client.Clients.Client_Result)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Handle Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  Consume and return the completed result exactly once.
   --
   --  @return Async_Not_Ready before completion,
   --          Async_Result_Already_Taken after the first successful consume, or
   --          the stored operation status when Value is copied out.

   procedure Shutdown
     (Item           : in out Async_Client;
      Cancel_Pending : Boolean := False);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Cancel_Pending Subprogram parameter.
   --  Stop accepting new work and wait for owned workers to stop.
   --
   --  If Cancel_Pending is False, queued requests are allowed to run before
   --  workers exit. If True, queued requests are completed as Async_Cancelled;
   --  active blocking requests are allowed to finish or observe cancellation
   --  according to the normal best-effort policy.

private
   protected type Future_State is
      procedure Request_Cancel
        (Status : out Http_Client.Errors.Result_Status);
      --  GNATdoc contract.
      --  @param Status Subprogram parameter.
      procedure Force_Cancel;
      function Cancellation_Requested return Boolean;
      --  GNATdoc contract.
      --  @return Subprogram result.
      procedure Mark_Started (May_Start : out Boolean);
      --  GNATdoc contract.
      --  @param May_Start Subprogram parameter.
      procedure Complete (Value : Http_Client.Clients.Client_Result);
      --  GNATdoc contract.
      --  @param Value Subprogram parameter.
      function Poll_Status return Http_Client.Errors.Result_Status;
      --  GNATdoc contract.
      --  @return Subprogram result.
      entry Await (Status : out Http_Client.Errors.Result_Status);
      procedure Consume
        (Value  : out Http_Client.Clients.Client_Result;
         Status : out Http_Client.Errors.Result_Status);
      --  GNATdoc contract.
      --  @param Value Subprogram parameter.
      --  @param Status Subprogram parameter.
   private
      Started   : Boolean := False;
      Done      : Boolean := False;
      Cancelled : Boolean := False;
      Taken     : Boolean := False;
      Stored    : Http_Client.Clients.Client_Result;
   end Future_State;

   type Future_Access is access all Future_State;

   type State;
   type State_Access is access all State;

   type Request_Handle is record
      ID     : Natural := 0;
      Future : Future_Access := null;
      Owner  : State_Access := null;
   end record;

   type Async_Client is new Ada.Finalization.Limited_Controlled with record
      Pool_State   : State_Access := null;
      Config       : Async_Configuration := Default_Async_Configuration;
      Was_Shutdown : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Async_Client);
   --  GNATdoc contract.
   --  @param Item Async client being finalized.
end Http_Client.Async;
