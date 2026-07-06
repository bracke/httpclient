# Phase 16 Response Streams Task Abort Cleanup Pass

This pass fixes a remaining AUnit reporting hang in `Http_Client.Response_Streams.Tests`.

The response-stream suite contains several local server/proxy task objects used by
individual test cases.  If an assertion fails or a client path returns before the
server/proxy task reaches its normal completion point, Ada waits for the local
task at scope finalization.  That can prevent the AUnit text reporter from ever
printing the final report.

The affected response-stream tests now abort their local fixture task on normal
exit and in the exception path.  This keeps failures local to the test case and
prevents a dependent local task from blocking the suite finalization path.

No warning suppression was added.  No C test fixtures or pthread-based fixtures
were added.
