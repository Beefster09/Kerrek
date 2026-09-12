package resolver

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import "../../common"
import "../ast"
import "../diagnostics"
import "../parser"
import "../units"


KERREK_FILE_EXTENSION :: ".krk"

Resolver :: struct {
	project_root:   string,
	next_symbol_id: common.Symbol_ID,
	packages:       map[string]^Package,
	files:          map[string]^File,
	arena:          mem.Dynamic_Arena,
	allocator:      runtime.Allocator,
}

Load_Error :: enum {
	OK,
	Not_Found,
	Not_A_Directory,
	Not_A_File,
	Cannot_Read,
	Syntax_Error,
	Cannot_Resolve_Path,
	Other_OS_Error,
}

init :: proc(res: ^Resolver, project_root := "") {
	mem.dynamic_arena_init(&res.arena)
	res.allocator = mem.dynamic_arena_allocator(&res.arena)
	res.packages = make(map[string]^Package)
	res.next_symbol_id = FIRST_USER_SYMBOL_ID

	if project_root != "" {
		cleaned, err := filepath.clean(project_root, res.allocator)
		res.project_root = cleaned if err == nil else project_root
	} else {
		root, err := os.get_working_directory(res.allocator)
		res.project_root = root if err == nil else "."
	}
}

destroy :: proc(res: ^Resolver) {
	mem.dynamic_arena_destroy(&res.arena)
	res^ = {}
}

load_package :: proc(
	res: ^Resolver,
	path: string,
	file_as_package := false,
) -> (
	^Package,
	Load_Error,
) {
	abs_path, path_err := filepath.abs(path, context.temp_allocator)
	if path_err != nil {
		return nil, .Cannot_Resolve_Path
	}

	if cached, ok := res.packages[abs_path]; ok {
		return cached, .OK
	}

	pkg := new(Package, res.allocator)
	pkg.defined_symbols = make(map[Identifier]Partial_Symbol)

	if file_as_package {
		pkg.name = Identifier(
			strings.intern_get(&common.ident_intern, filepath.stem(abs_path)) or_else panic(
				"unable to intern package name",
			),
		)
		file, err := _load_file(res, pkg, path)
		if err != nil {
			return nil, err
		}

		pkg.files = make([]^File, 1, res.allocator)
		pkg.files[0] = file

	} else {
		fd, open_err := os.open(abs_path)
		if open_err != nil {
			switch open_err {
			case os.General_Error.Not_Exist:
				return nil, .Not_Found
			case:
				return nil, .Other_OS_Error
			}
		}
		defer os.close(fd)

		dir_iter := os.read_directory_iterator_create(fd)
		defer os.read_directory_iterator_destroy(&dir_iter)

		for entry, _ in os.read_directory_iterator(&dir_iter) {
			// TODO
		}
	}

	return pkg, .OK
}

_load_file :: proc(res: ^Resolver, pkg: ^Package, path: string) -> (^File, Load_Error) {
	abs_path, path_err := filepath.abs(path, context.temp_allocator)
	if path_err != nil {
		return nil, .Other_OS_Error
	}

	if cached, ok := res.files[abs_path]; ok {
		return cached, .OK
	}

	file_ast, parse_err := parser.parse(abs_path)
	if parse_err != .OK {
		return nil, .Syntax_Error
	}

	file := new(File, res.allocator)
	file.own_package = pkg

	// Source_File owns a stable copy of the absolute path.
	res.files[file_ast.source.file] = file

	// Cache before descending so cyclic imports terminate.
	for decl in file_ast.declarations {
		_add_symbol(res, file, decl)
	}

	for imp in file.imports {
		panic("TODO")
		/*
		import_path, namespace, ok := _import_target(res, file, imp)
		if !ok {
			continue
		}

		if previous, exists := module.imports[namespace]; exists {
			diagnostics.emit(
				.Import_Conflict,
				imp.span,
				"import of '%s' conflicts with existing import of '%s'",
				import_path,
				previous.file.source.file,
			)
		}

		imported, import_err := require(res, import_path)
		if import_err != .OK {
			diagnostics.emit(
				.Import_Not_Found,
				imp.span,
				"cannot load imported module '%s'",
				import_path,
			)
			continue
		}
		module.imports[namespace] = imported

		for used_name in imp.using_names {
			if symbol := module_lookup_defined(imported, used_name.id); symbol != nil {
				if previous := module_lookup(module, used_name.id); previous != nil {
					diag := diagnostics.emit(
						.Duplicate_Definition,
						used_name.span,
						"imported name '%s' conflicts with an existing name",
						used_name.id,
					)
					if previous_span, has_span := named_span(previous); has_span {
						diagnostics.reference(
							diag,
							previous_span,
							"'%s' was previously defined here",
							used_name.id,
						)
					}
				}
				module.using_symbols[used_name.id] = symbol
			} else {
				diagnostics.emit(
					.Unresolved_Name,
					used_name.span,
					"module '%s' does not define '%s'",
					namespace,
					used_name.id,
				)
			}
		}
		*/
	}

	return file, .OK
}

file_lookup :: proc(file: ^File, name: Identifier) -> Named {
	if imp, ok := file.imports[name]; ok {
		return imp.pkg
	}
	if defined, ok := file.own_package.defined_symbols[name]; ok {
		return _to_named(defined)
	}
	for _, imp in file.imports {
		for using_name in imp.use_names {
			if name == using_name.id {
				if symbol, ok := imp.pkg.defined_symbols[name]; ok {
					return _to_named(symbol)
				}
			}
		}
	}
	return nil
}

scope_lookup :: proc(scope: ^Scope, name: Identifier) -> Named {
	scope := scope
	for {
		if symbol, ok := scope.locals[name]; ok {
			return _to_named(symbol)
		}

		switch parent in scope.parent {
		case ^Scope:
			scope = parent
		case ^File:
			return file_lookup(parent, name)
		case:
			return nil
		}
	}
}

partial_resolve :: proc {
	partial_resolve_qualname,
	partial_resolve_expression,
}

partial_resolve_qualname :: proc(
	qualname: ast.Qualified_Name,
	scope: ^Scope,
) -> (
	Named,
	[]Identifier,
) {
	return _resolve_qualname(scope, qualname), nil
}

partial_resolve_expression :: proc(scope: ^Scope, expr: ast.Expression) -> (Named, []Identifier) {
	#partial switch node in expr {
	case ^ast.Name_Expr:
		return scope_lookup(scope, node.name.id), nil

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
		panic(fmt.tprintf("cannot resolve %T nodes", expr))
	}
}

resolve :: proc {
	resolve_qualname,
	resolve_expression,
}

resolve_qualname :: proc(scope: ^Scope, qualname: ast.Qualified_Name) -> Named {
	return _resolve_qualname(scope, qualname)
}

resolve_expression :: proc(scope: ^Scope, expr: ast.Expression) -> Named {
	named, unresolved := partial_resolve_expression(scope, expr)

	if named != nil && len(unresolved) > 0 {
		diagnostics.emit(
			.Incomplete_Resolution,
			_expression_span(expr),
			"cannot fully resolve this",
		)
		return nil
	}
	return named
}

_next_symbol_header :: proc(res: ^Resolver, name: Identifier) -> _Symbol_Header {
	header := _Symbol_Header {
		id   = res.next_symbol_id,
		name = name,
	}
	res.next_symbol_id += 1
	return header
}

_add_symbol :: proc(res: ^Resolver, file: ^File, decl: ast.Top_Level_Declaration) {
	switch node in decl {
	case ^ast.Func_Definition:
		_check_shadowing(file, node.name)
		symbol := new(Function, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Type_Alias:
		_check_shadowing(file, node.name)
		symbol := new(Type_Alias, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Constant_Def:
		_check_shadowing(file, node.name)
		symbol := new(Constant, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Global_Variable:
		_check_shadowing(file, node.name)
		symbol := new(Global_Variable, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Unit_Type_Decl:
		_check_shadowing(file, node.name)
		symbol := new(Unit_Type, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Unit_Type_Alias_Decl:
		_check_shadowing(file, node.name)
		symbol := new(Unit_Type_Alias, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Unit_Decl:
		_check_shadowing(file, node.name)
		symbol := new(Base_Unit, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)
		units.register_unit_name(symbol.id, symbol.name)

	case ^ast.Unit_Alias_Decl:
		_check_shadowing(file, node.name)
		symbol := new(Unit_Alias, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Capability_Decl:
		_check_shadowing(file, node.name)
		symbol := new(Capability, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)

	case ^ast.Annotation_Def:
		_check_shadowing(file, node.name)
		symbol := new(Annotation, res.allocator)
		symbol^ = {_next_symbol_header(res, node.name.id), node, nil}
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)
	}
}

_check_shadowing :: proc(file: ^File, name: ast.Name) {
	if builtin_lookup(name.id) != nil {
		diagnostics.emit(.Builtin_Shadowing, name.span, "'%s' shadows a builtin name", name.id)
		return
	}

	if previous := file_lookup(file, name.id); previous != nil {
		diag := diagnostics.emit(
			.Duplicate_Definition,
			name.span,
			"'%s' conflicts with a previously defined name in the package",
			name.id,
		)
		if previous_span, ok := named_span(previous); ok {
			diagnostics.reference(diag, previous_span, "'%s' was previously defined here", name.id)
		}
	}
}

_static_resolve_field :: proc(base: Named, field: ast.Name) -> Named {
	#partial switch symbol in base {
	case ^Package:
		if sym, ok := symbol.defined_symbols[field.id]; ok {
			return _to_named(sym)
		}
	case ^Base_Unit:
		_emit_namespace_error(field, symbol.name, "base unit")
	case ^Unit_Type:
		_emit_namespace_error(field, symbol.name, "unit type")
	case ^Function:
		_emit_namespace_error(field, symbol.name, "function")
	case ^Capability:
		_emit_namespace_error(field, symbol.name, "capability")
	}
	return nil
}

_emit_namespace_error :: proc(field: ast.Name, base_name: Identifier, kind: string) {
	diagnostics.emit(
		.Invalid_Namespace_Access,
		field.span,
		"cannot get field '%s' of '%s' because it is a %s, which never has a namespace",
		field.id,
		base_name,
		kind,
	)
}

_resolve_qualname :: proc(scope: ^Scope, qualname: ast.Qualified_Name) -> Named {
	if len(qualname.path) == 0 do return nil

	base_name := qualname.path[0]
	resolved := scope_lookup(scope, base_name.id)
	if resolved == nil {
		diagnostics.emit(.Unresolved_Name, base_name.span, "cannot resolve '%s'", base_name.id)
		return nil
	}

	for field, i in qualname.path[1:] {
		resolved = _static_resolve_field(resolved, field)
		if resolved == nil {
			diagnostics.emit(
				.Unresolved_Name,
				field.span,
				"cannot resolve component %d of this qualified name",
				i + 2,
			)
			return nil
		}
	}
	return resolved
}

_to_named :: proc(symbol: Partial_Symbol) -> Named {
	switch value in symbol {
	case ^Function:
		return value
	case ^Type_Alias:
		return value
	case ^Distinct_Type:
		return value
	case ^Struct_Type:
		return value
	case ^Enum_Type:
		return value
	case ^Constant:
		return value
	case ^Global_Variable:
		return value
	case ^Local_Variable:
		return value
	case ^Unit_Type:
		return value
	case ^Base_Unit:
		return value
	case ^Unit_Type_Alias:
		return value
	case ^Unit_Alias:
		return value
	case ^Capability:
		return value
	case ^Annotation:
		return value
	case ^Formal_Parameter:
		return value
	case ^Named_Return:
		return value
	case:
		return nil
	}
}

_type_definition_to_named :: proc(symbol: Type_Definition) -> Named {
	switch value in symbol {
	case ^Type_Alias:
		return value
	case ^Distinct_Type:
		return value
	case ^Struct_Type:
		return value
	case ^Enum_Type:
		return value
	case:
		return nil
	}
}

named_span :: proc(named: Named) -> (common.Span, bool) {
	#partial switch symbol in named {
	case ^Function:
		return symbol.ast.name.span, true
	case ^Type_Alias:
		return symbol.ast.name.span, true
	case ^Constant:
		return symbol.ast.name.span, true
	case ^Global_Variable:
		return symbol.ast.name.span, true
	case ^Local_Variable:
		return symbol.ast.name.span, true
	case ^Unit_Type:
		return symbol.ast.name.span, true
	case ^Base_Unit:
		return symbol.ast.name.span, true
	case ^Unit_Type_Alias:
		return symbol.ast.name.span, true
	case ^Unit_Alias:
		return symbol.ast.name.span, true
	case ^Capability:
		return symbol.ast.name.span, true
	case ^Annotation:
		return symbol.ast.name.span, true
	case ^Formal_Parameter:
		return symbol.ast.name.span, true
	case ^Named_Return:
		if symbol.ast.name != nil do return symbol.ast.name.?.span, true
	}
	return {}, false
}

_expression_span :: proc(expr: ast.Expression) -> common.Span {
	switch node in expr {
	case ^ast.Name_Expr:
		return node.span
	case ^ast.FieldAccess_Expr:
		return node.span
	case ^ast.Placeholder_Expr:
		return node.span
	case ^ast.Scalar_Literal_Expr:
		return node.span
	case ^ast.Simple_Literal_Expr:
		return node.span
	case ^ast.Implicit_Enum_Expr:
		return node.span
	case ^ast.Move_Expr:
		return node.span
	case ^ast.Binop_Expr:
		return node.span
	case ^ast.Unary_Expr:
		return node.span
	case ^ast.Address_Of_Expr:
		return node.span
	case ^ast.Dereference_Expr:
		return node.span
	case ^ast.Cast_Expr:
		return node.span
	case ^ast.Unit_Conversion_Expr:
		return node.span
	case ^ast.Unit_Reinterpret_Expr:
		return node.span
	case ^ast.Index_Expr:
		return node.span
	case ^ast.Callish_Expr:
		return node.span
	case ^ast.Type_Expr_Expr:
		return node.span
	case ^ast.Unit_Expr:
		return node.span
	case:
		return {}
	}
}

_import_target :: proc(
	res: ^Resolver,
	from: ^File,
	imp: ^ast.Import,
) -> (
	path: string,
	namespace: Identifier,
	ok: bool,
) {
	panic("TODO")
}
