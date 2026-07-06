package Http_Client.Transports
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Transport namespace for raw byte-oriented HTTP and HTTPS backends.
   --
   --  Plain HTTP uses the Http_Client.Transports.TCP child package. HTTPS/TLS
   --  uses the OpenSSL-backed Http_Client.Transports.TLS child package.

   type Transport_Kind is
     (Plain_HTTP,
      HTTPS_TLS);
   --  Transport categories recognized by the library.

   function Is_Implemented (Kind : Transport_Kind) return Boolean;
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @return Subprogram result.
   --  Return True for both currently implemented transport categories.
end Http_Client.Transports;
