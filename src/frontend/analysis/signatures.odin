package analysis

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


Signature_Type_Context :: struct {
	generics: map[common.Identifier]^hir.Generic_Type,
}


// analyze_declaration_signatures is the second semantic pass. Dependencies are
// processed recursively, but function bodies and annotation applications are
// only queued so source order cannot affect callable signatures.
analyze_declaration_signatures :: proc(state: ^Translation_State) -> bool {
	assert(state != nil)
	if !prepare_declaration_graph(state) {
		return false
	}

	ok := true
	for pkg in state.symbol_resolver.loaded_packages {
		for file in pkg.files {
			ctx := Declaration_Context {
				translation = state,
				file        = file,
			}
			for symbol in file.defined_symbols {
				ok = process_declaration_signature(ctx, symbol) && ok
			}
		}
	}

	if state.output.entry_point == nil {
		diagnostics.emit(
			.Missing_Entry_Point,
			{},
			"entry package does not define a 'main' function",
		)
		ok = false
	} else if !_validate_entry_point(state.output.entry_point) {
		ok = false
	}

	return ok
}


process_declaration_signature :: proc(
	caller_ctx: Declaration_Context,
	symbol: resolver.Partial_Symbol,
	reference_span: common.Span = {},
) -> bool {
	switch begin_declaration(caller_ctx, symbol, reference_span) {
	case .Already_Done:
		return true
	case .Failed, .Cycle:
		return false
	case .Ready:
	}

	header := resolver.partial_symbol_header(symbol)
	ctx := Declaration_Context {
		translation = caller_ctx.translation,
		file        = header.defined_in if header.defined_in != nil else caller_ctx.file,
	}
	succeeded := _build_declaration_signature(ctx, symbol)
	return finish_declaration(ctx.translation, symbol, succeeded)
}


_build_declaration_signature :: proc(
	ctx: Declaration_Context,
	symbol: resolver.Partial_Symbol,
) -> bool {
	switch value in symbol {
	case ^resolver.Unit_Type:
		annotations, ok := _build_annotations(ctx, value.ast.annotations)
		value.hir.annotations = annotations
		return ok

	case ^resolver.Unit_Type_Alias:
		canonical, ok := get_canonical_unit(ctx, value.ast.orig, .Type)
		if ok {
			value.canonical = canonical
		}
		// Alias annotations remain source-facing on the resolver symbol because
		// aliases canonicalize away in HIR.
		_, annotations_ok := _build_annotations(ctx, value.ast.annotations)
		return ok && annotations_ok

	case ^resolver.Base_Unit:
		ok := true
		if len(value.ast.unit_type.path) > 0 {
			resolved := resolver.resolve_qualname(_resolution_parent(ctx), value.ast.unit_type)
			#partial switch unit_type in resolved {
			case ^resolver.Unit_Type:
				ok = process_declaration_signature(ctx, unit_type, value.ast.unit_type.span)
				if ok {
					value.hir.type = unit_type.hir
				}
			case:
				diagnostics.emit(
					.Invalid_Unit,
					value.ast.unit_type.span,
					"base unit '%s' must name a declared unit type",
					value.name,
				)
				ok = false
			}
		}
		annotations, annotations_ok := _build_annotations(ctx, value.ast.annotations)
		value.hir.annotations = annotations
		return ok && annotations_ok

	case ^resolver.Unit_Alias:
		canonical, ok := get_canonical_unit(ctx, value.ast.orig, .Value)
		if ok {
			value.canonical = canonical
		}
		_, annotations_ok := _build_annotations(ctx, value.ast.annotations)
		return ok && annotations_ok

	case ^resolver.Type_Alias:
		type_ctx: Signature_Type_Context
		resolved, ok := resolve_signature_type(ctx, value.ast.type, &type_ctx)
		if ok {
			value.hir = resolved
		}
		_, annotations_ok := _build_annotations(ctx, value.ast.annotations)
		return ok && annotations_ok

	case ^resolver.Function:
		return _build_function_signature(ctx, value)

	case ^resolver.Annotation:
		return _build_annotation_definition(ctx, value)

	case ^resolver.Capability:
		annotations, ok := _build_annotations(ctx, value.ast.annotations)
		value.hir.annotations = annotations
		return ok

	case ^resolver.Constant:
		return true // we'll deal with these later

	case ^resolver.Global_Variable:
		type_ctx: Signature_Type_Context
		ok := true
		if value.ast.type != nil {
			value.hir.type, ok = resolve_signature_type(ctx, value.ast.type, &type_ctx)
		}
		resolved_unit, unit_ok := resolve_declared_unit(ctx, value.ast.unit)
		value.hir.unit = resolved_unit
		annotations, annotations_ok := _build_annotations(ctx, value.ast.annotations)
		value.hir.annotations = annotations
		return ok && unit_ok && annotations_ok

	case ^resolver.Distinct_Type, ^resolver.Struct_Type, ^resolver.Enum_Type:
		// The resolver reserves stable nodes for these, but the parser does not
		// produce their declaration forms yet.
		return true

	case ^resolver.Local_Variable, ^resolver.Formal_Parameter, ^resolver.Named_Return:
		// Local signature nodes are constructed by their owning function/body.
		return true
	}
	return false
}


_resolution_parent :: proc(ctx: Declaration_Context) -> resolver.Scope_Parent {
	if ctx.scope != nil {
		return ctx.scope
	}
	return ctx.file
}


resolve_declared_unit :: proc(
	ctx: Declaration_Context,
	declared: ast.Declared_Unit,
) -> (
	hir.Realized_Unit,
	bool,
) {
	switch unit in declared {
	case ^ast.Compound_Unit:
		canonical, ok := get_canonical_unit(ctx, unit)
		if !ok {
			return nil, false
		}
		return canonical, true
	case ast.Indeterminate_Unit:
		switch unit {
		case .No_Unit:
			return hir.Indeterminate_Unit.No_Unit, true
		case .Flexible, .Inferred:
			return hir.Indeterminate_Unit.Flexible, true
		}
	case nil:
		return hir.Indeterminate_Unit.Flexible, true
	}
	return nil, false
}


resolve_signature_type :: proc(
	ctx: Declaration_Context,
	type_expr: ast.Type_Expression,
	type_ctx: ^Signature_Type_Context,
) -> (
	hir.Type,
	bool,
) {
	if type_expr == nil {
		return nil, false
	}

	switch node in type_expr {
	case ^ast.Simple_Type:
		resolved := resolver.resolve_qualname(_resolution_parent(ctx), node.type)
		if resolved == nil {
			return nil, false
		}

		#partial switch symbol in resolved {
		case ^resolver.Builtin:
			#partial switch symbol.kind {
			case .Primitive_Type:
				return _primitive_type(symbol)
			case .Parameterized_Type:
				diagnostics.emit(
					.Invalid_Type,
					node.span,
					"builtin type '%s' requires arguments",
					symbol.name,
				)
				return nil, false
			case:
				diagnostics.emit(
					.Invalid_Type,
					node.span,
					"builtin '%s' is not a type",
					symbol.name,
				)
				return nil, false
			}

		case ^resolver.Type_Alias:
			if process_declaration_signature(ctx, symbol, node.span) {
				return symbol.hir, true
			}

		case ^resolver.Distinct_Type:
			if process_declaration_signature(ctx, symbol, node.span) {
				return symbol.hir, true
			}

		case ^resolver.Struct_Type:
			if process_declaration_signature(ctx, symbol, node.span) {
				return symbol.hir, true
			}

		case ^resolver.Enum_Type:
			if process_declaration_signature(ctx, symbol, node.span) {
				return symbol.hir, true
			}

		case:
			diagnostics.emit(
				.Invalid_Type,
				node.span,
				"'%s' does not name a type",
				node.type.path[len(node.type.path) - 1].id,
			)
		}
		return nil, false

	case ^ast.Optional_Type:
		base, ok := resolve_signature_type(ctx, node.base, type_ctx)
		if !ok {
			return nil, false
		}
		context.allocator = ctx.translation.output.allocator
		result := new(hir.Optional_Type)
		result.base = base
		return result, true

	case ^ast.Pointer_Type:
		to, ok := resolve_signature_type(ctx, node.to, type_ctx)
		if !ok {
			return nil, false
		}
		context.allocator = ctx.translation.output.allocator
		result := new(hir.Pointer_Type)
		result.to = to
		result.ownership = node.ownership
		result.nullable = false
		return result, true

	case ^ast.Type_With_Tags:
		base, ok := resolve_signature_type(ctx, node.base, type_ctx)
		if !ok {
			return nil, false
		}
		context.allocator = ctx.translation.output.allocator
		tags := make([dynamic]hir.Symbol_ID, 0, len(node.tags))
		for tag in node.tags {
			resolved := resolver.resolve_qualname(_resolution_parent(ctx), tag)
			if resolved == nil {
				ok = false
				continue
			}
			if builtin, is_builtin := resolved.(^resolver.Builtin); is_builtin {
				append(&tags, builtin.id)
			} else if partial := _named_as_partial(resolved); partial != nil {
				if process_declaration_signature(ctx, partial, tag.span) {
					append(&tags, resolver.partial_symbol_header(partial).id)
				} else {
					ok = false
				}
			} else {
				diagnostics.emit(.Invalid_Type, tag.span, "this name cannot be used as a type tag")
				ok = false
			}
		}
		if !ok {
			return nil, false
		}
		shrink(&tags)
		result := new(hir.Tagged_Type)
		result.base = base
		result.tags = tags[:]
		return result, true

	case ^ast.Generic_Type:
		if type_ctx == nil {
			diagnostics.emit(.Invalid_Type, node.span, "generic types are not valid here")
			return nil, false
		}
		if type_ctx.generics == nil {
			context.allocator = ctx.translation.scratch_allocator
			type_ctx.generics = make(map[common.Identifier]^hir.Generic_Type)
		}
		if existing, found := type_ctx.generics[node.name.id]; found {
			return existing, true
		}
		context.allocator = ctx.translation.output.allocator
		generic := new(hir.Generic_Type)
		generic.name = node.name.id
		type_ctx.generics[node.name.id] = generic
		if node.bound != nil {
			bound, ok := resolve_signature_type(ctx, node.bound, type_ctx)
			if !ok {
				return nil, false
			}
			generic.bound = bound
		}
		return generic, true

	case ^ast.Type_With_Args:
		diagnostics.emit(
			.Invalid_Type,
			node.span,
			"generic type arguments require compile-time expression analysis",
		)
		return nil, false
	}
	return nil, false
}


_primitive_type :: proc(builtin: ^resolver.Builtin) -> (hir.Primitive_Type, bool) {
	switch builtin.name {
	// The unsized language-level defaults use the widest required primitive
	// representation until range-driven narrowing is implemented.
	case "Int128":
		return .Int128, true
	case "Int64":
		return .Int64, true
	case "Int32":
		return .Int32, true
	case "Int16":
		return .Int16, true
	case "Int8":
		return .Int8, true
	case "UInt128":
		return .UInt128, true
	case "UInt64":
		return .UInt64, true
	case "UInt32":
		return .UInt32, true
	case "UInt16":
		return .UInt16, true
	case "UInt8":
		return .UInt8, true
	case "Float64":
		return .Bin64, true
	case "Float32":
		return .Bin32, true
	case "Float16":
		return .Bin16, true
	case "Boolean":
		return .Boolean, true
	case "String":
		return .String, true
	case "Rune":
		return .Rune, true
	case "Byte":
		return .Byte, true
	case "Any":
		return .Any, true
	case "Opaque":
		return .Opaque, true
	case "Opaque8":
		return .Opaque8, true
	case "Opaque16":
		return .Opaque16, true
	case "Opaque32":
		return .Opaque32, true
	case "Opaque64":
		return .Opaque64, true
	}

	return {}, false
}


_build_function_signature :: proc(ctx: Declaration_Context, symbol: ^resolver.Function) -> bool {
	type_ctx: Signature_Type_Context
	context.allocator = ctx.translation.output.allocator
	params := make([dynamic]^hir.Formal_Parameter, 0, len(symbol.ast.params))
	returns := make([dynamic]^hir.Func_Return, 0, len(symbol.ast.returns))
	ok := true

	for ast_param, i in symbol.ast.params {
		if previous_span, duplicate := _find_parameter_name(
			symbol.ast.params[:i],
			ast_param.name.id,
		); duplicate {
			diagnostics.emit(
				.Duplicate_Local,
				ast_param.name.span,
				"duplicate parameter name '%s'",
				ast_param.name.id,
			)
			ok = false
			continue
		}

		param, param_ok := _build_formal_parameter(ctx, ast_param, &type_ctx)
		if param_ok {
			append(&params, param)
		} else {
			ok = false
		}
	}

	for ast_return, i in symbol.ast.returns {
		return_type, type_ok := resolve_signature_type(ctx, ast_return.type, &type_ctx)
		return_unit, unit_ok := resolve_declared_unit(ctx, ast_return.unit)
		if !type_ok || !unit_ok {
			ok = false
			continue
		}

		context.allocator = ctx.translation.output.allocator
		result := new(hir.Func_Return)
		result^ = {
			span = ast_return.span,
			type = return_type,
			unit = return_unit,
		}
		append(&returns, result)

		if ast_return.name != nil {
			if previous_span, duplicate := _find_return_name(
				symbol.ast.returns[:i],
				ast_return.name.?.id,
			); duplicate {
				diagnostics.emit(
					.Duplicate_Local,
					ast_return.name.?.span,
					"duplicate return name '%s'",
					ast_return.name.?.id,
				)
				ok = false
			}
		}
	}

	if symbol.ast.error_type != nil {
		error_type, error_ok := resolve_signature_type(ctx, symbol.ast.error_type, &type_ctx)
		symbol.hir.error_type = error_type
		ok = error_ok && ok
	}
	symbol.hir.fallible = symbol.ast.fallible

	if symbol.ast.requires != nil {
		requires, requires_ok := _build_capability_expression(ctx, symbol.ast.requires)
		if requires_ok {
			context.allocator = ctx.translation.output.allocator
			symbol.hir.requires = new(hir.Capability_Expression)
			symbol.hir.requires^ = requires
		} else {
			ok = false
		}
	}

	annotations, annotations_ok := _build_annotations(ctx, symbol.ast.annotations)
	symbol.hir.annotations = annotations
	ok = annotations_ok && ok
	shrink(&params)
	shrink(&returns)
	symbol.hir.params = params[:]
	symbol.hir.returns = returns[:]

	if ok {
		append(&ctx.translation.pending_bodies, Pending_Function_Body{symbol = symbol})
		if symbol.defined_in.own_package == ctx.translation.entry_package &&
		   symbol.name == "main" {
			if ctx.translation.output.entry_point == nil {
				ctx.translation.output.entry_point = symbol.hir
			} else {
				diag := diagnostics.emit(
					.Invalid_Entry_Point,
					symbol.ast.name.span,
					"entry package defines more than one 'main' function",
				)
				diagnostics.reference(
					diag,
					ctx.translation.output.entry_point.name.span,
					"the previous entry point was defined here",
				)
				ok = false
			}
		}
	}
	return ok
}


_build_formal_parameter :: proc(
	ctx: Declaration_Context,
	ast_param: ^ast.Formal_Parameter,
	type_ctx: ^Signature_Type_Context,
) -> (
	^hir.Formal_Parameter,
	bool,
) {
	param_type, type_ok := resolve_signature_type(ctx, ast_param.type, type_ctx)
	param_unit, unit_ok := resolve_declared_unit(ctx, ast_param.unit)
	if !type_ok || !unit_ok {
		return nil, false
	}

	context.allocator = ctx.translation.output.allocator
	param := new(hir.Formal_Parameter)
	param.span = ast_param.span
	param.id = _next_symbol_id(ctx.translation)
	param.name = ast_param.name
	param.type = param_type
	param.unit = param_unit
	return param, true
}


_find_parameter_name :: proc(
	params: []^ast.Formal_Parameter,
	name: common.Identifier,
) -> (
	common.Span,
	bool,
) {
	for param in params {
		if param.name.id == name {
			return param.name.span, true
		}
	}
	return {}, false
}


_find_return_name :: proc(
	returns: []^ast.Func_Return,
	name: common.Identifier,
) -> (
	common.Span,
	bool,
) {
	for result in returns {
		if result.name != nil && result.name.?.id == name {
			return result.name.?.span, true
		}
	}
	return {}, false
}


_build_annotation_definition :: proc(
	ctx: Declaration_Context,
	symbol: ^resolver.Annotation,
) -> bool {
	type_ctx: Signature_Type_Context
	context.allocator = ctx.translation.output.allocator
	params := make([dynamic]^hir.Formal_Parameter, 0, len(symbol.ast.args))
	ok := true
	for ast_param, i in symbol.ast.args {
		if previous_span, duplicate := _find_parameter_name(
			symbol.ast.args[:i],
			ast_param.name.id,
		); duplicate {
			diag := diagnostics.emit(
				.Duplicate_Local,
				ast_param.name.span,
				"annotation parameter '%s' is already defined",
				ast_param.name.id,
			)
			diagnostics.reference(
				diag,
				previous_span,
				"annotation parameter '%s' was previously defined here",
				ast_param.name.id,
			)
			ok = false
			continue
		}
		param, param_ok := _build_formal_parameter(ctx, ast_param, &type_ctx)
		if param_ok {
			append(&params, param)
		} else {
			ok = false
		}
	}
	shrink(&params)
	symbol.hir.params = params[:]
	annotations, annotations_ok := _build_annotations(ctx, symbol.ast.annotations)
	symbol.hir.annotations = annotations
	return ok && annotations_ok
}


_build_annotations :: proc(
	ctx: Declaration_Context,
	ast_annotations: []^ast.Annotation,
) -> (
	[]^hir.Annotation,
	bool,
) {
	context.allocator = ctx.translation.output.allocator
	annotations := make([dynamic]^hir.Annotation, 0, len(ast_annotations))
	ok := true

	for ast_annotation in ast_annotations {
		resolved := resolver.resolve_qualname(_resolution_parent(ctx), ast_annotation.base)
		if resolved == nil {
			ok = false
			continue
		}

		#partial switch definition in resolved {
		case ^resolver.Annotation:
			if !process_declaration_signature(ctx, definition, ast_annotation.base.span) {
				ok = false
				continue
			}
			annotation := new(hir.Annotation)
			annotation.span = ast_annotation.span
			annotation.definition = definition.hir
			append(&annotations, annotation)
			append(
				&ctx.translation.pending_annotations,
				Pending_Annotation_Application {
					ast = ast_annotation,
					hir = annotation,
					definition = definition,
					file = ctx.file,
				},
			)

		case ^resolver.Builtin:
			if definition.kind != .Annotation {
				diagnostics.emit(
					.Invalid_Annotation,
					ast_annotation.span,
					"builtin '%s' is not an annotation",
					definition.name,
				)
				ok = false
			}
		// Builtin annotations drive compiler behavior and do not need a
		// source-defined Annotation_Def node in HIR.

		case:
			diagnostics.emit(
				.Invalid_Annotation,
				ast_annotation.span,
				"'%s' does not name an annotation",
				ast_annotation.base.path[len(ast_annotation.base.path) - 1].id,
			)
			ok = false
		}
	}

	shrink(&annotations)
	return annotations[:], ok
}


_build_capability_expression :: proc(
	ctx: Declaration_Context,
	ast_expr: ast.Capability_Expression,
) -> (
	hir.Capability_Expression,
	bool,
) {
	switch node in ast_expr {
	case ^ast.Named_Capability:
		resolved := resolver.resolve_qualname(_resolution_parent(ctx), node.capability)
		#partial switch capability in resolved {
		case ^resolver.Capability:
			if process_declaration_signature(ctx, capability, node.capability.span) {
				return capability.hir, true
			}
		case:
			diagnostics.emit(
				.Invalid_Capability,
				node.capability.span,
				"this name does not denote a capability",
			)
		}

	case ^ast.All_Capabilities:
		context.allocator = ctx.translation.output.allocator
		subs := make([dynamic]hir.Capability_Expression, 0, len(node.capabilities))
		for child in node.capabilities {
			sub, ok := _build_capability_expression(ctx, child)
			if !ok {
				return nil, false
			}
			append(&subs, sub)
		}
		shrink(&subs)
		result := new(hir.Capability_All_Of)
		result.span = node.span
		result.subs = subs[:]
		return result, true

	case ^ast.Any_Capabilities:
		context.allocator = ctx.translation.output.allocator
		subs := make([dynamic]hir.Capability_Expression, 0, len(node.capabilities))
		for child in node.capabilities {
			sub, ok := _build_capability_expression(ctx, child)
			if !ok {
				return nil, false
			}
			append(&subs, sub)
		}
		shrink(&subs)
		result := new(hir.Capability_Any_Of)
		result.span = node.span
		result.subs = subs[:]
		return result, true
	}
	return nil, false
}


_named_as_partial :: proc(named: resolver.Named) -> resolver.Partial_Symbol {
	#partial switch symbol in named {
	case ^resolver.Function:
		return symbol
	case ^resolver.Type_Alias:
		return symbol
	case ^resolver.Distinct_Type:
		return symbol
	case ^resolver.Struct_Type:
		return symbol
	case ^resolver.Enum_Type:
		return symbol
	case ^resolver.Constant:
		return symbol
	case ^resolver.Global_Variable:
		return symbol
	case ^resolver.Local_Variable:
		return symbol
	case ^resolver.Unit_Type:
		return symbol
	case ^resolver.Base_Unit:
		return symbol
	case ^resolver.Unit_Type_Alias:
		return symbol
	case ^resolver.Unit_Alias:
		return symbol
	case ^resolver.Capability:
		return symbol
	case ^resolver.Annotation:
		return symbol
	case ^resolver.Formal_Parameter:
		return symbol
	case ^resolver.Named_Return:
		return symbol
	}
	return nil
}


_next_symbol_id :: proc(state: ^Translation_State) -> common.Symbol_ID {
	id := state.symbol_resolver.next_symbol_id
	state.symbol_resolver.next_symbol_id += 1
	return id
}


_validate_entry_point :: proc(entry: ^hir.Func_Definition) -> bool {
	ok := true
	if len(entry.params) != 0 {
		diagnostics.emit(
			.Invalid_Entry_Point,
			entry.name.span,
			"func 'main' must not accept parameters",
		)
		ok = false
	}
	if len(entry.returns) != 0 {
		diagnostics.emit(
			.Invalid_Entry_Point,
			entry.name.span,
			"func 'main' must not return values",
		)
		ok = false
	}
	if entry.fallible {
		diagnostics.emit(.Invalid_Entry_Point, entry.name.span, "func 'main' must not be fallible")
		ok = false
	}
	return ok
}
