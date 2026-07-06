package Http_Client.Resources is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Optional process-local resource counters for diagnostics, benchmark
   --  smoke tests, and leak-oriented regression tests.
   --
   --  These counters are intentionally observational. They do not participate
   --  in protocol decisions, retry policy, cache keys, TLS verification,
   --  fallback policy, or public request/response semantics. Implementations
   --  update them only at resource ownership boundaries that are already
   --  explicit in the public API. Reset_All is intended for deterministic
   --  tests and benchmark executables, not for production accounting.

   type Counter_Kind is
     (Streaming_Responses_Open,
      Async_Clients_Open,
      Async_Workers_Configured,
      Pool_Idle_Entries,
      Persistent_Cache_Stores_Open,
      Diagnostics_Events_Emitted);

   type Resource_Snapshot is record
      Streaming_Responses_Open      : Natural := 0;
      Async_Clients_Open            : Natural := 0;
      Async_Workers_Configured      : Natural := 0;
      Pool_Idle_Entries             : Natural := 0;
      Persistent_Cache_Stores_Open  : Natural := 0;
      Diagnostics_Events_Emitted    : Natural := 0;
   end record;

   procedure Increment (Kind : Counter_Kind; Amount : Natural := 1);
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @param Amount Subprogram parameter.
   --  Add Amount to Kind, saturating at Natural'Last. Zero Amount is a no-op.

   procedure Decrement (Kind : Counter_Kind; Amount : Natural := 1);
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @param Amount Subprogram parameter.
   --  Subtract Amount from Kind, saturating at zero to keep cleanup paths
   --  idempotent and safe after partially initialized resources.

   procedure Reset_All;
   --  Reset all counters to zero. Intended for deterministic tests.

   function Snapshot return Resource_Snapshot;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return a consistent snapshot of all counters.

   function Value (Kind : Counter_Kind) return Natural;
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @return Subprogram result.
   --  Return the current value for Kind.
end Http_Client.Resources;
