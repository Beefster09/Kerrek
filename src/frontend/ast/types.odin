package ast

import "../../common"

Type_Alias :: struct {
	span:        Span,
	name:        Name,
	type:        Type_Expression,
	annotations: []^Annotation,
}

Struct_Def :: struct {
	span:         Span,
	name:         Name,
	fields:       []^Struct_Field,
	facts:        []^Fact_Decl,
	capabilities: []^Capability_Decl,
	annotations:  []^Annotation,
}

Struct_Field :: struct {
	span:        Span,
	name:        Name,
	requires:    Capability_Expression,
	annotations: []^Annotation,
}

Type_Expression :: union {
	^Simple_Type,
	^Type_With_Args,
	^Generic_Type,
	^Optional_Type,
	^Pointer_Type,
	^Type_With_Tags,
}

type_span :: proc(type: Type_Expression) -> Span {
	switch type in type {
	case ^Simple_Type:
		return type.span
	case ^Type_With_Args:
		return type.span
	case ^Generic_Type:
		return type.span
	case ^Optional_Type:
		return type.span
	case ^Pointer_Type:
		return type.span
	case ^Type_With_Tags:
		return type.span
	}

	return {}
}

Simple_Type :: struct {
	span: Span,
	type: Qualified_Name,
}

Type_With_Args :: struct {
	span: Span,
	base: Qualified_Name,
	args: []Argument,
}

Generic_Type :: struct {
	span:  Span,
	name:  Name,
	bound: Type_Expression,
}

Optional_Type :: struct {
	span: Span,
	base: Type_Expression,
}

Pointer_Type :: struct {
	span:      Span,
	to:        Type_Expression,
	ownership: common.Pointer_Ownership,
}

Type_With_Tags :: struct {
	span: Span,
	base: Type_Expression,
	tags: []Qualified_Name,
}
