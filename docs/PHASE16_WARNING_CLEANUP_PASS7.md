# Phase 16 Warning Cleanup Pass 7

This pass responds to the build output that followed pass 6.

The previous warning-cleanup pass became too aggressive in a few places. It removed import aspects from local OpenSSL fixture bindings and removed package use visibility that several large generated/scaffold tests still rely on for short-form calls.

Changes in this pass:

- Restored `with Import, Convention => C, External_Name => ...` aspects for the local OpenSSL fixture bindings in `Http_Client.Ada_Test_Fixtures`.
- Restored the import aspect for `SSL_CTX_callback_ctrl`.
- Restored `use Ada.Strings.Fixed` and `use Ada.Strings.Unbounded` visibility in the affected large test bodies where short-form `Index`, `Length`, `Element`, `Slice`, `Append`, `To_String`, `To_Unbounded_String`, `Unbounded_String`, and `Null_Unbounded_String` are intentionally used.
- Restored direct visibility for access-type equality in `Http_Client.Clients.Tests` for cookie jar and persistent cache store access values.

No warning suppression was added. No C test fixtures were reintroduced. No TLS defaults were weakened.
