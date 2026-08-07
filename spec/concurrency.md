# Concurrency

Concurrency in Kerrek revolves around a constrained async/await model atop a threaded task queue.

Every function call spawned with `async` creates a future object. There is no distinction between functions that can be called with `async` or not; all functions are callable with or without `async`. Future objects can be `await`ed, causing the current thread to wait until its task completes with a return value. Future objects are idempotent and can be `await`ed more than once; every `await` after the first simply retrieves the value or error that was returned.

All of the following situations produce a compile-time error:
- a future becomes unreachable without being awaited at least once in all paths through the function
- a borrowed pointer was passed to an awaited call, and the await is outside the scope where the pointer was borrowed
