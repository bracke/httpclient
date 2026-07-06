# HTTP/3

HTTP/3 and QUIC APIs are experimental in this release. They expose configuration, frame/stream/QPACK helpers, mapping, execution boundary, and backend availability status so applications and tests can opt in deliberately.

Production HTTP/3 execution is available only when a configured QUIC backend reports support. Unsupported configurations fail before request bytes are sent or fall back only under explicit before-send fallback policy. HTTP/3 through configured HTTP or SOCKS proxies is rejected rather than bypassing proxy policy. 0-RTT, server push cache, MASQUE, CONNECT-UDP, WebTransport, and browser-like discovery are not implemented.
