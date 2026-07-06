# Caching

Caching is disabled by default. `Http_Client.Cache` provides bounded in-memory cache behavior. `Http_Client.Cache.Persistent` provides explicit persistent and encrypted persistent stores.

Cache keys, Vary handling, freshness calculations, authenticated-response bypass, client-certificate sensitivity, and size limits are part of the documented cache behavior. Cache file bytes and encrypted-cache record layouts are implementation-owned unless a file-format version is explicitly documented as stable. Applications should expose a safe cache-clear path and may clear pre-release cache directories across incompatible versions.
