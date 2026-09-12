package resolver

import "base:intrinsics"

import "../../common"
import "../ast"
import "../hir"
import "../units"


Symbol_ID :: common.Symbol_ID
Identifier :: common.Identifier


_Symbol_Header :: struct {
	id:         Symbol_ID,
	name:       Identifier,
	state:      enum {
		Unprocessed,
		Processing,
		Done,
		Error,
	},
	defined_in: ^File,
}

Function :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Func_Definition,
	hir:     ^hir.Func_Definition,
}

Type_Alias :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Type_Alias,
	hir:     hir.Type,
}

// These type variants are not produced by the parser yet, but keeping the
// symbol shapes here makes the resolver ready for their AST nodes.
Distinct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     ^hir.Distinct_Type,
}

Struct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     ^hir.Struct_Type,
}

Enum_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr,
	hir:     ^hir.Enum_Type,
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
	hir:     ^hir.Global_Variable,
}

Local_Variable :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Local_Variable,
	hir:     ^hir.Local_Variable,
}

Unit_Type :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Type_Decl,
	hir:     ^hir.Unit_Type,
}

Base_Unit :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Decl,
	hir:     ^hir.Base_Unit,
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
	hir:     ^hir.Capability,
}

Annotation :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Annotation_Def,
	hir:     ^hir.Annotation_Def,
}

Formal_Parameter :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Formal_Parameter,
	hir:     ^hir.Formal_Parameter,
}

Named_Return :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Func_Return,
	hir:     ^hir.Func_Return,
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
