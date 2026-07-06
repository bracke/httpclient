# SPARK and GNATprove

HttpClient has a deliberately partial SPARK surface. The stable root package, status/error declarations, transport policy declarations, TLS option declarations, and selected HTTP/2 and HTTP/3 protocol-boundary helpers are annotated with `SPARK_Mode => On`; operations that depend on sockets, OpenSSL handles, tasking, dynamic containers, or stream state remain ordinary Ada or have local `SPARK_Mode => Off` islands.

The release legality check is:

```sh
alr exec -- gnatprove -P httpclient.gpr --level=4
```

This command is a release gate. It checks the currently annotated SPARK surface for legality without making the network, TLS, OpenSSL, and tasking implementation units part of a proof claim.

Run GNATprove through Alire only. The active manifests pin
`gnat_native = "=15.2.1"`, and `alr exec -- gnatls --version` must report
`GNATLS 15.x` before proof or release checks are valid.

Current SPARK-enabled public packages include:

- `Http_Client`
- `Http_Client.Errors`
- `Http_Client.Transports`
- `Http_Client.TLS`
- `Http_Client.Types`
- selected HTTP/2 and HTTP/3 settings, frame, stream, and QUIC boundary packages

When new pure value-level helpers are added, prefer enabling `SPARK_Mode => On` on the smallest package or subprogram that proves cleanly. Keep impure network execution, OpenSSL bridge, tasking, and filesystem/cache code outside the SPARK surface unless their contracts are intentionally designed for proof.
