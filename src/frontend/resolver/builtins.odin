package resolver

import "core:fmt"


FIRST_USER_SYMBOL_ID :: 10_000

// Builtin symbol IDs are assigned from declaration order by initialize. This
// keeps them deterministic without requiring each builtin to maintain its own
// ID, and makes adding a builtin unable to collide with an existing ID.
BUILTINS := [?]Builtin {
	// Types. Binary floats intentionally live in the intrinsics collection.
	{name = "Integer", kind = .Primitive_Type},
	{name = "Int64", kind = .Primitive_Type},
	{name = "Int32", kind = .Primitive_Type},
	{name = "Int16", kind = .Primitive_Type},
	{name = "Int8", kind = .Primitive_Type},
	{name = "UInt64", kind = .Primitive_Type},
	{name = "UInt32", kind = .Primitive_Type},
	{name = "UInt16", kind = .Primitive_Type},
	{name = "UInt8", kind = .Primitive_Type},
	{name = "Decimal", kind = .Primitive_Type},
	{name = "Dec64", kind = .Primitive_Type},
	{name = "Dec32", kind = .Primitive_Type},
	{name = "Boolean", kind = .Primitive_Type},
	{name = "String", kind = .Primitive_Type},
	{name = "Rune", kind = .Primitive_Type},
	{name = "Byte", kind = .Primitive_Type},
	{name = "Opaque", kind = .Primitive_Type},
	{name = "Opaque8", kind = .Primitive_Type},
	{name = "Opaque16", kind = .Primitive_Type},
	{name = "Opaque32", kind = .Primitive_Type},
	{name = "Opaque64", kind = .Primitive_Type},
	// Annotations.
	{name = "deprecated", kind = .Annotation},
	{name = "forward", kind = .Annotation},
	{name = "pure", kind = .Annotation},
	{name = "layout", kind = .Annotation},
	{name = "calling_convention", kind = .Annotation},
	// Functions.
	{name = "len", kind = .Function},
	{name = "cap", kind = .Function},
	{name = "append", kind = .Function},
	{name = "owned_shallow_clone", kind = .Function},
	{name = "owned_deep_clone", kind = .Function},
	{name = "shared_shallow_clone", kind = .Function},
	{name = "shared_deep_clone", kind = .Function},
}

_builtins_by_name: map[Identifier]Builtin

initialize :: proc() {
	_builtins_by_name = make(map[Identifier]Builtin)

	for &builtin, index in BUILTINS {
		builtin.id = Symbol_ID(index + 1)
		assert(
			builtin.id != 0 && builtin.id < FIRST_USER_SYMBOL_ID,
			fmt.tprintf("builtin %q has symbol ID %d outside the builtin range", builtin.name, builtin.id),
		)

		_, duplicate_name := _builtins_by_name[builtin.name]
		assert(!duplicate_name, fmt.tprintf("duplicate builtin name %q", builtin.name))
		_builtins_by_name[builtin.name] = builtin
	}
}

builtin_lookup :: proc(name: Identifier) -> Named {
	if builtin, ok := _builtins_by_name[name]; ok {
		return builtin
	}
	return nil
}
