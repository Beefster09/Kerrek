package resolver

import "base:intrinsics"

import "../../common"
import "../ast"
import "../units"


Symbol_ID :: common.Symbol_ID
Identifier :: common.Identifier


_Symbol_Header :: struct {
	id:         Symbol_ID,
	name:       Identifier,
	processed:  bool,
	defined_in: ^File,
}

Function :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Func_Definition,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Type_Alias :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Type_Alias,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

// These type variants are not produced by the parser yet, but keeping the
// symbol shapes here makes the resolver ready for their AST nodes.
Distinct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     rawptr,
}

Struct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     rawptr,
}

Enum_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     rawptr,
}

Type_Definition :: union {
	^Type_Alias,
	^Distinct_Type,
	^Struct_Type,
	^Enum_Type,
}

Constant :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Constant_Def,
	value:   rawptr, // TODO: replace with the compile-time value type
}

Global_Variable :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Global_Variable,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Local_Variable :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Local_Variable,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Unit_Type :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Type_Decl,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Base_Unit :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Decl,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Unit_Type_Alias :: struct {
	using _:   _Symbol_Header,
	ast:       ^ast.Unit_Type_Alias_Decl,
	canonical: units.Compound_Unit,
}

Unit_Alias :: struct {
	using _:   _Symbol_Header,
	ast:       ^ast.Unit_Alias_Decl,
	canonical: units.Compound_Unit,
	// These may still exist in the HIR for reflection purposes, e.g. printing
	// a kg m / s^2 as newtons.
}

Capability :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Capability_Decl,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Annotation :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Annotation_Def,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Formal_Parameter :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Formal_Parameter,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Named_Return :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Func_Return,
	hir:     rawptr, // TODO: replace when the HIR is ported
}

Partial_Symbol :: union {
	^Function,
	^Type_Alias,
	^Distinct_Type,
	^Struct_Type,
	^Enum_Type,
	^Constant,
	^Global_Variable,
	^Local_Variable,
	^Unit_Type,
	^Base_Unit,
	^Unit_Type_Alias,
	^Unit_Alias,
	^Capability,
	^Annotation,
	^Formal_Parameter,
	^Named_Return,
}

Builtin :: struct {
	id:   Symbol_ID,
	name: Identifier,
	kind: enum {
		Primitive_Type,
		Function,
		Annotation,
	},
}

Named :: intrinsics.type_merge(union {
		^Package,
		Builtin,
	}, Partial_Symbol)

Scope :: struct {
	locals: map[common.Identifier]Partial_Symbol,
	parent: union {
		^Scope,
		^File,
	},
}

Package :: struct {
	name:            Identifier,
	defined_symbols: map[Identifier]Partial_Symbol,
	files:           []^File,
}

File :: struct {
	src:             ^common.Source_File,
	src_ast:         ^ast.File,
	imports:         map[Identifier]Import,
	defined_symbols: [dynamic]Partial_Symbol,
	own_package:     ^Package,
}

Import :: struct {
	pkg:       ^Package,
	use_names: []ast.Name,
}
