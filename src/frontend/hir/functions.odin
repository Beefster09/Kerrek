package hir

import "base:runtime"

Func_Definition :: struct {
	using header: _Symbol_Header,
	params:       []^Formal_Parameter,
	returns:      []^Func_Return,
	error_type:   Type,
	requires:     Capability_Expression,
	flags:        Func_Flags,
	body:         ^Block,
	annotations:  []^Annotation,
	type:         ^Func_Type,
}

Func_Overload_Group :: struct {
	using _:   _Symbol_Header,
	overloads: []^Func_Definition,
}

Formal_Parameter :: struct {
	using _: _Symbol_Header,
	type:    Type,
	unit:    Realized_Unit,
	default: ^Const_Expr,
}

Func_Return :: struct {
	span: Span,
	type: Type,
	unit: Realized_Unit,
}

Func_Flags :: bit_set[Func_Flag;u32]
Func_Flag :: enum {
	Fallible,
	Pure,
	Diverges,
}


func_derive_type :: proc(func: ^Func_Definition, allocator: runtime.Allocator) {
	assert(func != nil)

	type := new(Func_Type, allocator)

	params := make([]Type_And_Unit, len(func.params), allocator)
	for p, i in func.params {
		params[i] = {
			type = p.type,
			unit = p.unit,
		}
	}

	returns := make([]Type_And_Unit, len(func.returns), allocator)
	for r, i in func.returns {
		returns[i] = {
			type = r.type,
			unit = r.unit,
		}
	}

	type^ = {
		params   = params,
		returns  = returns,
		error    = func.error_type,
		flags    = func.flags,
		requires = func.requires,
	}
	func.type = type
}
