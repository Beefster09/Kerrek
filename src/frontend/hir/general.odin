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

Type_Definition :: union {
	^Struct_Type,
	^Interface,
	^Enum_Type,
	^Distinct_Type,
}

Annotation_Def :: struct {
	using _:     _Symbol_Header,
	params:      []^Formal_Parameter,
	annotations: []^Annotation,
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

Base_Unit :: struct {
	using _:     _Symbol_Header,
	annotations: []^Annotation,
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
	using _:     _Symbol_Header,
	annotations: []^Annotation,
}

Capability_Expression :: union {
	^Capability,
	^Capability_All_Of,
	^Capability_Any_Of,
}

Capability_All_Of :: struct {
	span: Span,
	subs: []Capability_Expression,
}

Capability_Any_Of :: struct {
	span: Span,
	subs: []Capability_Expression,
}

// Poison nodes are used to mark translation failure points in an effort to avoid duplicate diagnostics
Poison :: struct {
	span: Span,
}
