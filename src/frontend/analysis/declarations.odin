package analysis

import "core:fmt"

import "../../common"
import "../diagnostics"
import "../hir"
import "../resolver"


Declaration_Start :: enum {
	Ready,
	Already_Done,
	Failed,
	Cycle,
}


// prepare_declaration_graph indexes every declaration currently loaded by the
// resolver and reserves stable HIR nodes for declarations that have HIR symbol
// identity. The nodes are deliberately left otherwise empty: later passes fill
// signatures and bodies without changing their addresses.
prepare_declaration_graph :: proc(state: ^Translation_State) -> bool {
	assert(state != nil)
	assert(state.symbol_resolver != nil)

	ok := true
	for pkg in state.symbol_resolver.loaded_packages {
		for file in pkg.files {
			for symbol in file.defined_symbols {
				ok = prepare_declaration(state, symbol) && ok
			}
		}
	}
	return ok
}


// prepare_declaration is idempotent. It is also called from begin_declaration
// so declarations introduced while translating a local scope receive the same
// identity and lifetime guarantees as eagerly collected globals.
prepare_declaration :: proc(state: ^Translation_State, symbol: resolver.Partial_Symbol) -> bool {
	assert(state != nil)
	assert(state.output != nil)

	header := resolver.partial_symbol_header(symbol)
	assert(header != nil)
	if existing, found := state.symbols_by_id[header.id]; found {
		if resolver.partial_symbol_header(existing) != header {
			fmt.assertf(false, "symbol ID %d belongs to more than one declaration", header.id)
			return false
		}
		return true
	}
	state.symbols_by_id[header.id] = symbol

	_init_header :: #force_inline proc(
		node: ^$T,
		span: common.Span,
		id: common.Symbol_ID,
		name: common.Name,
	) {
		node.span = span
		node.id = id
		node.name = name
	}

	context.allocator = state.output.allocator
	switch value in symbol {
	case ^resolver.Function:
		if value.hir == nil {
			value.hir = new(hir.Func_Definition)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.funcs, value.hir)
		}

	case ^resolver.Distinct_Type:
		if value.hir == nil {
			value.hir = new(hir.Distinct_Type)
			_init_header(value.hir, {}, value.id, {id = value.name})
			append(&state.hir_items.types, value.hir)
		}

	case ^resolver.Struct_Type:
		if value.hir == nil {
			value.hir = new(hir.Struct_Type)
			_init_header(value.hir, {}, value.id, {id = value.name})
			append(&state.hir_items.types, value.hir)
		}

	case ^resolver.Enum_Type:
		if value.hir == nil {
			value.hir = new(hir.Enum_Type)
			_init_header(value.hir, {}, value.id, {id = value.name})
			append(&state.hir_items.types, value.hir)
		}

	case ^resolver.Global_Variable:
		if value.hir == nil {
			value.hir = new(hir.Global_Variable)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.variables, value.hir)
		}

	case ^resolver.Local_Variable:
		if value.hir == nil {
			value.hir = new(hir.Local_Variable)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
		}

	case ^resolver.Unit_Type:
		if value.hir == nil {
			value.hir = new(hir.Unit_Type)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.unit_types, value.hir)
		}

	case ^resolver.Base_Unit:
		if value.hir == nil {
			value.hir = new(hir.Base_Unit)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.units, value.hir)
		}

	case ^resolver.Capability:
		if value.hir == nil {
			value.hir = new(hir.Capability)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.capabilities, value.hir)
		}

	case ^resolver.Annotation:
		if value.hir == nil {
			value.hir = new(hir.Annotation_Def)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
			append(&state.hir_items.annotations, value.hir)
		}

	case ^resolver.Formal_Parameter:
		if value.hir == nil {
			value.hir = new(hir.Formal_Parameter)
			_init_header(value.hir, value.ast.span, value.id, value.ast.name)
		}

	case ^resolver.Type_Alias,
	     ^resolver.Constant,
	     ^resolver.Unit_Type_Alias,
	     ^resolver.Unit_Alias,
	     ^resolver.Named_Return:
	// These symbols lower to canonical values or positional metadata rather
	// than independently addressable HIR declarations.
	}

	return true
}


// begin_declaration must be paired with finish_declaration when it returns
// Ready. A Processing declaration is a back-edge in the dependency graph. It
// is failed immediately so the same cycle cannot produce another diagnostic.
begin_declaration :: proc(
	ctx: Declaration_Context,
	symbol: resolver.Partial_Symbol,
	reference_span: common.Span = {},
) -> Declaration_Start {
	state := ctx.translation
	assert(state != nil)
	if !prepare_declaration(state, symbol) {
		return .Failed
	}

	header := resolver.partial_symbol_header(symbol)
	switch header.state {
	case .Done:
		return .Already_Done
	case .Failed:
		return .Failed
	case .Processing:
		_emit_declaration_cycle(state, symbol, reference_span)
		return .Cycle
	case .Unseen:
		header.state = .Processing
		append(&state.processing_stack, symbol)
		return .Ready
	}
	return .Failed
}


finish_declaration :: proc(
	state: ^Translation_State,
	symbol: resolver.Partial_Symbol,
	succeeded: bool,
) -> bool {
	assert(state != nil)
	header := resolver.partial_symbol_header(symbol)
	assert(header != nil)

	assert(len(state.processing_stack) > 0)
	top := state.processing_stack[len(state.processing_stack) - 1]
	fmt.assertf(
		resolver.partial_symbol_header(top) == header,
		"declarations must finish in reverse dependency order",
	)
	pop(&state.processing_stack)

	// A cycle may have changed this declaration to Failed while a recursive
	// processor was active. Never overwrite that failure on unwind.
	if header.state == .Processing {
		header.state = .Done if succeeded else .Failed
	}
	return header.state == .Done
}


_emit_declaration_cycle :: proc(
	state: ^Translation_State,
	symbol: resolver.Partial_Symbol,
	reference_span: common.Span,
) {
	header := resolver.partial_symbol_header(symbol)
	span := reference_span
	if span.file == 0 {
		span, _ = resolver.span_of_name(symbol)
	}
	diag := diagnostics.emit(
		.Declaration_Cycle,
		span,
		"declaration dependency cycle involving '%s'",
		header.name,
	)

	cycle_start := -1
	for item, i in state.processing_stack {
		if resolver.partial_symbol_header(item) == header {
			cycle_start = i
			break
		}
	}
	assert(cycle_start >= 0)
	for item in state.processing_stack[cycle_start:] {
		item_header := resolver.partial_symbol_header(item)
		item_header.state = .Failed
		if item_span, ok := resolver.span_of_name(item); ok {
			diagnostics.reference(
				diag,
				item_span,
				"'%s' participates in this dependency cycle",
				item_header.name,
			)
		}
	}
}
