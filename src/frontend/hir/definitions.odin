package hir


Struct_Field :: struct {
	span:        Span,
	name:        Name,
	type:        Type,
	requires:    ^Capability_Expression,
	annotations: []^Annotation,
}

Struct_Type :: struct {
	using _:            _Symbol_Header,
	fields:             []^Struct_Field,
	params:             []^Formal_Parameter,
	capabilities:       []^Capability,
	construct_requires: ^Capability_Expression,
	annotations:        []^Annotation,
}

Interface_Method :: struct {
	span:         Span,
	name:         Name,
	params:       []^Formal_Parameter,
	return_types: []Type,
	error_type:   Type,
	fallible:     bool,
	requires:     ^Capability_Expression,
	is_optional:  bool,
}

Sub_Interface :: struct {
	span:        Span,
	interface:   ^Interface,
	is_optional: bool,
}

Interface_Item :: union {
	^Interface_Method,
	^Sub_Interface,
}

Interface :: struct {
	using _:     _Symbol_Header,
	methods:     []Interface_Item,
	annotations: []^Annotation,
}

Interface_Impl :: struct {
	using _:     _Symbol_Header,
	impls:       []^Func_Definition,
	annotations: []^Annotation,
}

Enum_Variant :: struct {
	span:    Span,
	name:    Maybe(Name),
	payload: Type,
	slot:    int,
}

Enum_Type :: struct {
	using _:     _Symbol_Header,
	variants:    []^Enum_Variant,
	annotations: []^Annotation,
}

Distinct_Type :: struct {
	using _:     _Symbol_Header,
	underlying:  Type,
	annotations: []^Annotation,
}
