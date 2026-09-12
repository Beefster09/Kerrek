package hir

import "base:runtime"

import "../../common"
import "../units"


Span :: common.Span
Symbol_ID :: common.Symbol_ID
Identifier :: common.Identifier


Translation_Unit :: struct {
	entry_point: ^Func_Definition,
	types:        map[Symbol_ID]Type_Definition,
	funcs:        map[Symbol_ID]^Func_Definition,
	variables:    map[Symbol_ID]^Global_Variable,
	unit_types:   map[Symbol_ID]^Unit_Type,
	units:        map[Symbol_ID]^Base_Unit,
	capabilities: map[Symbol_ID]^Capability,
	annotations:  map[Symbol_ID]^Annotation_Def,
}

init :: proc(tu: ^Translation_Unit, allocator: runtime.Allocator = context.allocator) {
	tu.types = make(map[Symbol_ID]Type_Definition, allocator = allocator)
	tu.funcs = make(map[Symbol_ID]^Func_Definition, allocator = allocator)
	tu.variables = make(map[Symbol_ID]^Global_Variable, allocator = allocator)
	tu.unit_types = make(map[Symbol_ID]^Unit_Type, allocator = allocator)
	tu.units = make(map[Symbol_ID]^Base_Unit, allocator = allocator)
	tu.capabilities = make(map[Symbol_ID]^Capability, allocator = allocator)
	tu.annotations = make(map[Symbol_ID]^Annotation_Def, allocator = allocator)
}

destroy :: proc(tu: ^Translation_Unit) {
	delete(tu.types)
	delete(tu.funcs)
	delete(tu.variables)
	delete(tu.unit_types)
	delete(tu.units)
	delete(tu.capabilities)
	delete(tu.annotations)
	tu^ = {}
}

_Symbol_Header :: struct {
	span: Span,
	id:   Symbol_ID,
}

_Annotatable_Header :: struct {
	using _:     _Symbol_Header,
	annotations: []^Annotation,
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
	name:    Identifier,
	params:  []^Formal_Parameter,
}

Annotation :: struct {
	span:       Span,
	definition: ^Annotation_Def,
	args:       []Argument,
}

Global_Variable :: struct {
	using _: _Annotatable_Header,
	name:    Identifier,
	type:    Type,
	unit:    Realized_Unit,
	expr:    Expression,
}

Unit_Type :: struct {
	using _: _Symbol_Header,
	name:    Identifier,
}

Base_Unit :: struct {
	using _: _Symbol_Header,
	name:    Identifier,
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
	name:    Identifier,
}

// Capability expressions are intentionally opaque until capability analysis is
// ported. Keeping a source span and a distinct type avoids using rawptr at HIR
// call sites while leaving room for the eventual all/any/named node union.
Capability_Expression :: struct {
	span: Span,
}
