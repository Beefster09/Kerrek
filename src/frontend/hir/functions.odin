package hir

import "base:runtime"

Func_Definition :: struct {
	using header: _Symbol_Header,
	params:       []^Formal_Parameter,
	ret:          ^Func_Return,
	err:          Type,
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

	return_value: ^Type_And_Unit
	if func.ret != nil {
		return_value = new(Type_And_Unit, allocator)
		return_value^ = {
			type = func.ret.type,
			unit = func.ret.unit,
		}
	}

	type^ = {
		params   = params,
		ret      = return_value,
		err      = func.err,
		flags    = func.flags,
		requires = func.requires,
	}
	func.type = type
}
