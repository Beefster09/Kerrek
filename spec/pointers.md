# Pointers

A pointer carries some ownership semantics

If a pointer may possibly be nil (either by its default semantics or by being deliberately nullable), then it is an error to dereference it without first checking its validity.

## `owned`

An owned pointer points to storage that is guaranteed to be able to outlive the scope in which it was created.

The value it points to is destroyed as soon as the owned pointer becomes unreachable.

Owned pointers may not be assigned into other owned pointers, only moved

## `shared`

An shared pointer points to storage that is guaranteed to be able to outlive the scope in which it was created.

The value it points to is reference counted, and *must* be destroyed when there are no shared references remaining which point to the value.

Shared pointers may only be assigned from other shared pointers.

## `weak`

A weak pointer may point to either owned or shared values, or any interior values of some other owned or shared value. They may be assigned from `owned`, `shared`, or `weak` pointers

Weak pointers do not keep shared or owned values alive and become semantically `nil` when the value they pointed to is destroyed. Exactly how this is implemented is left to the compiler. As such, weak pointers are always nullable.

Weak pointers make no guarantees about validity across concurrency boundaries; it is theoretically possible for a race condition to exist between checking the validity of a weak pointer and dereferencing it. In practice, creating a situation where this could happen would require deliberate subversion of the async/await concurrency model.

## Borrow pointer `^`

Borrow pointers may be assigned from `owned`, `shared`, or `weak` pointers or any interior values thereof.

Borrow pointers may not outlive the scope they were assigned from.

## `unsafe_ptr`

These pointers primarily exist for C interop and make no promises about lifetime or validity.

They are always nullable.
