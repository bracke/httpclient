package Http_Client.TLS
  with SPARK_Mode => On
is
   --  Release surface: implementation detail.
   --  This package is visible to other Ada units in this source tree but
   --  is not part of the stable application compatibility contract.
   --  TLS-specific public support packages.
   --
   --  TLS credentials are transport-layer credentials. They are not HTTP
   --  Authorization headers and configuring them never disables ordinary
   --  server-certificate or hostname verification.
end Http_Client.TLS;
