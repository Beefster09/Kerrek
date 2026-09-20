package resolver

import "base:runtime"
import "core:fmt"
import "core:slice"

import "../../common"
import "../ast"
import "../diagnostics"


Lexical_Scope :: struct {
	locals: map[common.Identifier]Symbol,
	parent: Scope,
}

Scope :: union {
	^Lexical_Scope,
	^File,
}

new_scope :: proc(parent: Scope, allocator: runtime.Allocator) -> ^Lexical_Scope {
	scope := new(Lexical_Scope, allocator)
	scope^ = {
		parent = parent,
		locals = make(map[common.Identifier]Symbol),
	}
	return scope
}

@(deferred_out_by_ptr = _destroy_local_scope)
temp_scope :: proc(parent: Scope) -> Lexical_Scope {
	return {parent = parent, locals = make(map[common.Identifier]Symbol, context.temp_allocator)}
}

_destroy_local_scope :: proc(scope: ^Lexical_Scope) {
	delete(scope.locals)
}


Define_Local_Error :: enum {
	OK,
	Conflict,
}


define_local :: proc(
	scope: ^Lexical_Scope,
	name: common.Name,
	symbol: Symbol,
) -> Define_Local_Error {
	if existing, exists := scope.locals[name.id]; exists {
		diag := diagnostics.emit(
			.Duplicate_Local,
			name.span,
			"name '%s' is already defined",
			name.id,
		)
		if name_span, ok := span_of_name(existing); ok {
			diagnostics.reference(diag, name_span, "'%s' was previously defined here", name.id)
		}
		return .Conflict
	}

	scope.locals[name.id] = symbol

	return .OK
}

lookup :: proc(scope: Scope, name: Identifier) -> Symbol {
	scope := scope
	outer: for {
		switch current in scope {
		case ^Lexical_Scope:
			if symbol, ok := current.locals[name]; ok {
				return symbol
			}
			scope = current.parent
		case ^File:
			if symbol := file_lookup(current, name); symbol != nil {
				return symbol
			}
			break outer
		case:
			break outer
		}
	}

	if name in _builtins_prelude {
		return _builtins_prelude[name]
	}

	return nil
}

partial_resolve :: proc {
	partial_resolve_qualname,
	partial_resolve_expression,
}

partial_resolve_qualname :: proc(
	qualname: ast.Qualified_Name,
	scope: Scope,
) -> (
	Symbol,
	[]Identifier,
) {
	return _resolve_qualname(scope, qualname), nil
}

partial_resolve_expression :: proc(scope: Scope, expr: ast.Expression) -> (Symbol, []Identifier) {
	#partial switch node in expr {
	case ^ast.Name_Expr:
		return lookup(scope, node.name.id), nil

	case ^ast.FieldAccess_Expr:
		base, rest := partial_resolve_expression(scope, node.base)
		if base != nil {
			if field := _static_resolve_field(base, node.field); field != nil {
				return field, nil
			}
		}

		unresolved := slice.concatenate(
			[][]Identifier{{node.field.id}, rest},
			allocator = context.temp_allocator,
		)
		return base, unresolved[:]

	case:
		fmt.panicf("cannot resolve %T nodes", expr)
	}
}

resolve :: proc {
	resolve_qualname,
	resolve_expression,
}

resolve_qualname :: proc(scope: Scope, qualname: ast.Qualified_Name) -> Symbol {
	return _resolve_qualname(scope, qualname)
}

resolve_expression :: proc(scope: Scope, expr: ast.Expression) -> Symbol {
	named, unresolved := partial_resolve_expression(scope, expr)

	if named != nil && len(unresolved) > 0 {
		diagnostics.emit(
			.Incomplete_Resolution,
			expression_span(expr),
			"cannot fully resolve this",
		)
		return nil
	}
	return named
}
