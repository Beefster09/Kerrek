# `if`/`else`

if, else if, and else blocks require a boolean or nullable as the condition

the condition is not parenthesized, but the braces are mandatory:

```kerrek
if some_pointer { \\ not nil
    fmt.println("pointer is not nil");
} else if another_condition and yet_another {
    fmt.println("both are true");
} else {
    fmt.println("fallback condition");
}
```

# `switch`/`case`

You can `switch` on any singular value. There is no opening brace before the cases. Every `case` requires braces:

```kerrek
switch some_enum
case .One {
    return x;
}
case .Two {
    return y;
}
case .Three {
    return z;
}
```

Each case is a distinct scope and there is no fallthrough. `break` *does not bind to the switch*.

# Loops

Loops are denoted with the `loop` keyword. There are 5 loop forms.


```kerrek
loop item in 0 ..< 10 {
    \\ bounded loop over exclusive range
}
loop item in 1 ..= 10 {
    \\ bounded loop over inclusive range
}
loop item in some_slice {
    \\ bounded loop over a slice without the index
}
loop i, item in some_slice {
    \\ bounded loop over a slice with the index
}
loop key, value in some_map {
    \\ bounded loop over map
}
```

```kerrek
loop
    step let item = next_item(&iterator)
    while item
{
    \\ the "while (item = next())" loop, but without making assignment an expression
    \\ the step clause runs before the first while clause, and on each iteration
    \\ the step clause may, but does not have to, declare variables in this position
}
```

```kerrek
loop
    let i = 1
    while i < 256
    step i *= 2
{
    \\ the "3-clause for" loop
}
```

```kerrek
loop {
    \\ the "do while" loop
} while after_condition;
```

```kerrek
loop {
    \\ unconditional loop
}
```
