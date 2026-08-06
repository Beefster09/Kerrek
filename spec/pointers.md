# `owned`

An owned pointer points to storage that is guaranteed to be able to outlive the scope in which it was created.

The value it points to is destroyed as soon as the owned pointer becomes unreachable.

Owned pointers may not be copied into other owned pointers, only moved

# `shared`

An shared pointer points to storage that is guaranteed to be able to outlive the scope in which it was created.

The value it points to is reference counted, and *must* be destroyed when there are no shared references remaining which point to the value.

Shared pointers may only be assigned from other shared pointers.

# `weak`

A weak pointer may point to either owned or shared values, or any interior values of some other owned or shared value. They may be assigned from `owned`, `shared`, or `weak` pointers

Weak pointers do not keep shared or owned values alive and become semantically `nil` when the value they pointed to is destroyed. Exactly how this is implemented is left to the compiler. As such, weak pointers are always nullable.

# Borrow pointer `^`

Borrow pointers may be assigned from `owned`, `shared`, or `weak` pointers or any interior values thereof.

Borrow pointers may not outlive the scope they were assigned from.

# `unsafe_ptr`

These pointers primarily exist for C interop and make no promises about lifetime or validity.

They are always nullable.
