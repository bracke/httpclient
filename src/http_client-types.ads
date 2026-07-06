package Http_Client.Types
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   pragma Pure;

   --  Shared public scalar types for the Http_Client library.
   --
   --  These definitions are intentionally small and stable so request,
   --  response, parser, and transport APIs share common public vocabulary.

   type Method_Name is
     (GET,
      HEAD,
      POST,
      PUT,
      PATCH,
      DELETE,
      OPTIONS);
   --  Supported HTTP method names for request construction, HTTP/1.1
   --  serialization, redirect policy, retry classification, and high-level
   --  convenience methods.

   subtype Status_Code is Integer range 100 .. 599;
   --  Valid HTTP status-code range for parsed responses, redirect policy,
   --  retry policy, cache policy, and diagnostics metadata.
end Http_Client.Types;
