# Async

Async execution is explicit and bounded. The 1.0.0 API does not create a hidden global worker pool. Queue lengths, worker counts, cancellation behavior, shutdown behavior, and ownership of submitted requests are part of the configured async object.

Types should be treated as not concurrently mutable unless their package documentation states otherwise. If a caller shares clients, caches, cookie jars, diagnostics contexts, or streams across tasks, it must follow the documented task-safety rules for those objects.
