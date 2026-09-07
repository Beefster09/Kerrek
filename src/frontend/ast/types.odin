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

Simple_Type :: struct {
	type: Qualified_Name,
}

Type_With_Args :: struct {
	base: Qualified_Name,
	args: []Argument,
}

Generic_Type :: struct {
	name:  Name,
	bound: Type_Expression,
}

Optional_Type :: struct {
	base: Type_Expression,
}

Pointer_Type :: struct {
	to:        Type_Expression,
	ownership: common.Pointer_Ownership,
}

Type_With_Tags :: struct {
	base: Type_Expression,
	tags: []Qualified_Name,
}
