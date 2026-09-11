package resolver

import "../../common"
import "../ast"
import "../units"

_Symbol_Header :: struct {
	id:        common.Symbol_ID,
	name:      common.Identifier,
	processed: bool,
}

Function :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Distinct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Struct_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Enum_Type :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Constant :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	value:   FlexibleValue,
}


Global_Variable :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Local_Variable :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Unit_Type :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Type_Decl,
	hir:     rawptr, // TODO
}


Base_Unit :: struct {
	using _: _Symbol_Header,
	ast:     ^ast.Unit_Decl,
	hir:     rawptr, // TODO
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
	// NOTE: these *might* still exist in the HIR for reflection purposes
	// e.g. printing a kg m / s^2 as newtons
}


Capability :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Annotation :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Formal_Parameter :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}


Named_Return :: struct {
	using _: _Symbol_Header,
	ast:     rawptr, // TODO
	hir:     rawptr, // TODO
}
