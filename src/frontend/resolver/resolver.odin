package resolver

import "base:intrinsics"
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
	project_root:    string,
	next_symbol_id:  common.Symbol_ID,
	packages:        map[string]^Package,
	loaded_packages: [dynamic]^Package,
	files:           map[string]^File,
	units_by_id:     map[Symbol_ID]^Base_Unit,
	arena:           mem.Dynamic_Arena,
	allocator:       runtime.Allocator,
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
	res.packages = make(map[string]^Package, res.allocator)
	res.loaded_packages = make([dynamic]^Package, res.allocator)
	res.files = make(map[string]^File, res.allocator)
	res.units_by_id = make(map[Symbol_ID]^Base_Unit, res.allocator)
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
	pkg.defined_symbols = make(map[Identifier]Symbol, res.allocator)
	res.packages[abs_path] = pkg
	append(&res.loaded_packages, pkg)

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
	file^ = {
		src             = file_ast.source,
		src_ast         = file_ast,
		imports         = make(map[common.Identifier]^Import, res.allocator),
		defined_symbols = make([dynamic]Symbol, res.allocator),
		own_package     = pkg,
	}
	res.files[file_ast.source.file] = file

	for decl in file_ast.declarations {
		_add_global_symbol(res, file, decl)
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
						.Duplicate_Global,
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

file_lookup :: proc(file: ^File, name: Identifier) -> Symbol {
	if imp, ok := file.imports[name]; ok {
		return imp
	}
	if defined, ok := file.own_package.defined_symbols[name]; ok {
		return defined
	}
	for _, imp in file.imports {
		for using_name in imp.use_names {
			if name == using_name.id {
				if symbol, ok := imp.pkg.defined_symbols[name]; ok {
					return symbol
				}
			}
		}
	}
	return nil
}

new_symbol :: proc(
	res: ^Resolver,
	$T: typeid,
	name: Identifier,
) -> ^T where (intrinsics.type_field_type(T, "header") == _Symbol_Header) {
	symbol := new(T, res.allocator)
	symbol.id = intrinsics.atomic_add(&res.next_symbol_id, 1) // atomic add necessary for race conditions
	symbol.name = name
	return symbol
}

_add_global_symbol :: proc(res: ^Resolver, file: ^File, decl: ast.Top_Level_Declaration) {
	_real_add_symbol :: #force_inline proc(
		res: ^Resolver,
		file: ^File,
		node: $N,
		$S: typeid,
	) -> ^S {
		shadow := _check_shadowing(file, node.name)
		if shadow == .Shadows_Global || shadow == .Shadows_Import {
			return nil
		}
		symbol := new_symbol(res, S, node.name.id)
		symbol.ast = node
		symbol.defined_in = file
		file.own_package.defined_symbols[node.name.id] = symbol
		append(&file.defined_symbols, symbol)
		return symbol
	}

	switch node in decl {
	case ^ast.Func_Definition:
		_real_add_symbol(res, file, node, Function)

	case ^ast.Type_Alias:
		_real_add_symbol(res, file, node, Type_Alias)

	case ^ast.Constant_Def:
		_real_add_symbol(res, file, node, Constant)

	case ^ast.Global_Variable:
		_real_add_symbol(res, file, node, Global_Variable)

	case ^ast.Unit_Decl:
		symbol := _real_add_symbol(res, file, node, Base_Unit)
		if symbol != nil {
			res.units_by_id[symbol.id] = symbol
		}

	case ^ast.Unit_Alias_Decl:
		_real_add_symbol(res, file, node, Unit_Alias)

	case ^ast.Capability_Decl:
		_real_add_symbol(res, file, node, Capability)

	case ^ast.Annotation_Def:
		_real_add_symbol(res, file, node, Annotation)
	}
}

_check_shadowing :: proc(file: ^File, name: ast.Name) -> enum {
		No_Shadowing,
		Shadows_Import,
		Shadows_Global,
		Shadows_Builtin,
	} {

	if existing := file_lookup(file, name.id); existing != nil {
		#partial switch ex in existing {
		case ^Import:
			diag := diagnostics.emit(
				.Import_Conflict,
				name.span,
				"'%s' conflicts with an imported name in this file",
				name.id,
			)
			diagnostics.reference(diag, ex.local_name.span, "'%s' was imported here")
			return .Shadows_Import
		case:
			diag := diagnostics.emit(
				.Duplicate_Global,
				name.span,
				"'%s' conflicts with a previously defined name in the package",
				name.id,
			)
			if previous_span, ok := span_of_name(existing); ok {
				diagnostics.reference(
					diag,
					previous_span,
					"'%s' was previously defined here",
					name.id,
				)
			}
			return .Shadows_Global
		}
	}

	if builtin_lookup(name.id) != nil {
		diagnostics.emit(.Builtin_Shadowing, name.span, "'%s' shadows a builtin name", name.id)
		return .Shadows_Builtin
	}

	return .No_Shadowing
}

_static_resolve_field :: proc(base: Symbol, field: ast.Name) -> Symbol {
	#partial switch symbol in base {
	case ^Import:
		if sym, ok := symbol.pkg.defined_symbols[field.id]; ok {
			return sym
		}
	case ^Base_Unit:
		_emit_namespace_error(field, symbol.name, "base unit")
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

_resolve_qualname :: proc(parent: Scope, qualname: ast.Qualified_Name) -> Symbol {
	if len(qualname.path) == 0 do return nil

	base_name := qualname.path[0]
	resolved := lookup(parent, base_name.id)
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

symbol_name :: proc(named: Symbol) -> Identifier {
	switch symbol in named {
	case ^Import:
		return symbol.local_name.id
	case ^Builtin:
		return symbol.name
	case ^Function:
		return symbol.name
	case ^Type_Alias:
		return symbol.name
	case ^Constant:
		return symbol.name
	case ^Global_Variable:
		return symbol.name
	case ^Local_Variable:
		return symbol.name
	case ^Base_Unit:
		return symbol.name
	case ^Unit_Alias:
		return symbol.name
	case ^Capability:
		return symbol.name
	case ^Annotation:
		return symbol.name
	case ^Formal_Parameter:
		return symbol.name
	case ^Distinct_Type:
		return symbol.name
	case ^Struct_Type:
		return symbol.name
	case ^Enum_Type:
		return symbol.name
	case ^Named_Return:
		return symbol.name
	}
	return ""
}

span_of_name :: proc {
	symbol_span,
	expression_span,
}

symbol_span :: proc(named: Symbol) -> (common.Span, bool) {
	switch symbol in named {
	case ^Import:
		return symbol.local_name.span, true
	case ^Builtin:
		return {}, false
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
	case ^Base_Unit:
		return symbol.ast.name.span, true
	case ^Unit_Alias:
		return symbol.ast.name.span, true
	case ^Capability:
		return symbol.ast.name.span, true
	case ^Annotation:
		return symbol.ast.name.span, true
	case ^Formal_Parameter:
		return symbol.ast.name.span, true
	case ^Distinct_Type:
		return {}, false // TODO
	// return symbol.ast.name.span, true
	case ^Struct_Type:
		return {}, false // TODO
	// return symbol.ast.name.span, true
	case ^Enum_Type:
		return {}, false // TODO
	// return symbol.ast.name.span, true
	case ^Named_Return:
		if symbol.ast.name != nil {
			return symbol.ast.name.?.span, true
		}
	}
	return {}, false
}

expression_span :: proc(expr: ast.Expression) -> common.Span {
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
