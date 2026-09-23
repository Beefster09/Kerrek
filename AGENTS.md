# Spec

Do not modify the spec unless the BDFL (Justin Snyder) specifically asks you to do so.

# Comments

Do not comment code except to explain non-obvious quirks or nuances.
If a comment is necessary, keep it brief, ideally one line of 20 words or less.

# Tests

Do not modify tests to match current behavior. Fix the code, not the test.
If a test is inconsistent with the spec, fix the test, not the spec.
When writing a test, mutate the implementation to check that you're testing real behavior
Do not write trivial tests
Prefer table-based tests when possible

Test end-to-end as much as possible. For instance, semantic analysis passes should pass in the minimal amount of source code to produce the desired outcome rather than constructed AST.

Test diagnostic outputs against the Code enum and span, never the message or addendums.

# Refactoring

Use @(rodata) enumerated arrays whenever appropriate. If these are defined as (::) constants, prefer refactoring them into variables (:=) with @(rodata) instead of assigning the enumerated array to a local variable
