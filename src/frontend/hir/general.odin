package hir

import "base:runtime"
import "core:mem"

import "../../common"
import "../units"


Span :: common.Span
Symbol_ID :: common.Symbol_ID
Identifier :: common.Identifier
Name :: common.Name


Translation_Unit :: struct {
	entry_point:  ^Func_Definition,
	types:        []Type_Definition,
	funcs:        []^Func_Definition,
	variables:    []^Global_Variable,
	unit_types:   []^Unit_Type,
	units:        []^Base_Unit,
	capabilities: []^Capability,
	annotations:  []^Annotation_Def,
	arena:        mem.Dynamic_Arena,
	allocator:    runtime.Allocator,
}

init :: proc(tu: ^Translation_Unit) {
	mem.dynamic_arena_init(&tu.arena)
	tu.allocator = mem.dynamic_arena_allocator(&tu.arena)
}

destroy :: proc(tu: ^Translation_Unit) {
	mem.dynamic_arena_destroy(&tu.arena)
	tu^ = {}
}

_Symbol_Header :: struct {
	span: Span,
	id:   Symbol_ID,
	name: Name,
}

Symbol :: union {
	^Annotation_Def,
	^Global_Variable,
	^Unit_Type,
	^Base_Unit,
	^Capability,
	^Local_Variable,
	^Formal_Parameter,
	^Func_Definition,
	^Func_Overload_Group,
	^Struct_Type,
	^Interface,
	^Interface_Impl,
	^Enum_Type,
	^Distinct_Type,
}

Annotatable :: union {
	^Global_Variable,
	^Local_Variable,
	^Func_Definition,
	^Struct_Type,
	^Interface,
	^Interface_Impl,
	^Enum_Type,
	^Distinct_Type,
}

Type_Definition :: union {
	^Struct_Type,
	^Interface,
	^Enum_Type,
	^Distinct_Type,
}

Annotation_Def :: struct {
	using _: _Symbol_Header,
	params:  []^Formal_Parameter,
}

Annotation :: struct {
	span:       Span,
	definition: ^Annotation_Def,
	args:       []Argument,
}

Global_Variable :: struct {
	using _:     _Symbol_Header,
	type:        Type,
	unit:        Realized_Unit,
	expr:        Expression,
	annotations: []^Annotation,
}

Unit_Type :: struct {
	using _: _Symbol_Header,
}

Base_Unit :: struct {
	using _: _Symbol_Header,
	type:    ^Unit_Type,
}

Realized_Unit :: union {
	units.Compound_Unit,
	Indeterminate_Unit,
}

Indeterminate_Unit :: enum {
	Flexible,
	No_Unit,
}

Capability :: struct {
	using _: _Symbol_Header,
}

Capability_Expression :: struct {
	span: Span,
}
