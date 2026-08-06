# Interfaces are explicit

Methods don't exist. There are genuinely some situations where you need dynamic dispatch. Dynamic dispatch tends to make code hard to follow. That creates tension.

The resolution: add friction. Discourage interfaces and dynamic dispatch by making programmers explicitly define the vtable. If you're not absolutely sure you need an interface, do something else.

This also has a happy consequence: you can define multiple implementations of a vtable for the same type.

Interface objects have reference semantics.
