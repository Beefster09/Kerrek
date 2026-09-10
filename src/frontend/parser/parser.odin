package parser

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"

import "../../common"
import "../ast"
import "../diagnostics"
import "../lexer"


// external-facing parse error
Parse_Error :: enum {
	OK,
	Syntax_Error, // an unrecoverable syntax error
	Not_Found,
	Cannot_Read,
	Other_OS_Error,
}


parse :: proc(src_path: string) -> (file: ^ast.File, err: Parse_Error) {
	sf, ldsrc_err := common.load_source(src_path)
	switch ldsrc_err {
	case .Not_Found:
		return nil, .Not_Found
	case .Cannot_Read:
		return nil, .Cannot_Read
	case .Other_Error:
		return nil, .Other_OS_Error
	case .OK:
	// nothing to do; continue onward
	}
	defer common.unload_source(sf)

	ps := Parser_State {
		tokens = lexer.tokenize(sf),
	}
	defer delete(ps.tokens)

	file = new(ast.File)
	file.source = sf
	defer if err != .OK {
		free(file)
	}

	file.node_arena = new(mem.Dynamic_Arena)
	mem.dynamic_arena_init(file.node_arena)
	defer if err != .OK {
		mem.dynamic_arena_destroy(file.node_arena)
		free(file.node_arena)
	}

	temp_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temp_arena)
	defer mem.dynamic_arena_destroy(&temp_arena)

	{
		context.allocator = mem.dynamic_arena_allocator(file.node_arena)
		context.temp_allocator = mem.dynamic_arena_allocator(&temp_arena)

		err = _parse(&ps, file)
		if err != .OK {
			return nil, err
		}
	}

	return file, .OK
}


_parse :: proc(ps: ^Parser_State, file: ^ast.File) -> Parse_Error {
	annotations := make([dynamic]^ast.Annotation, context.temp_allocator)
	imports := make([dynamic]^ast.Import, context.temp_allocator)
	declarations := make([dynamic]ast.Top_Level_Declaration, 0, 256, context.temp_allocator)

	for node_raw in _toplevel_item(ps) {
		if node_raw == nil {
			continue
		}

		switch node in node_raw {
		case ^ast.Annotation:
			append(&annotations, node)

		case ^ast.Import:
			append(&imports, node)
			_attach_annotations(node, &annotations)

		case ^ast.Global_Constant:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Global_Variable:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Type_Alias:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Annotation_Def:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Unit_Type_Decl:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Unit_Type_Alias_Decl:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Unit_Decl:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Unit_Alias_Decl:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Capability_Decl:
			append(&declarations, node)
			_attach_annotations(node, &annotations)

		case ^ast.Func_Definition:
			append(&declarations, node)
			_attach_annotations(node, &annotations)
		}
	}

	file.imports = slice.clone(imports[:])
	file.declarations = slice.clone(declarations[:])

	return .OK
}

_toplevel_item :: proc(ps: ^Parser_State) -> (result: ast.Top_Level_Item, more: bool) {
	tok := _peek(ps) or_return

	switch tok.what {
	case Punctuation.At:
		anno := _annotation(ps)
		if anno == nil {
			_attempt_recovery(ps)
		}
		return anno, true

	case Keyword.Type:
		panic("not implemented")

	case Keyword.Let, Keyword.Const:
		decl := _const_or_var(ps, .Global)
		if _end_of_statement(ps) {
			switch d in decl {
			case ^ast.Global_Variable:
				return d, true
			case ^ast.Global_Constant:
				return d, true
			case ^ast.Local_Constant, ^ast.Local_Variable, nil:
				panic("got local var/constant")
			}
		} else {
			_attempt_recovery(ps)
			return nil, true
		}

	case Keyword.Unit:
		#partial switch decl in _unit_decl(ps) {
		case ^ast.Unit_Decl:
			return decl, true
		case ^ast.Unit_Alias_Decl:
			return decl, true
		case ^ast.Unit_Type_Decl:
			return decl, true
		case ^ast.Unit_Type_Alias_Decl:
			return decl, true
		case:
			return nil, true
		}

	case Keyword.Func:
		return _func_def(ps), true

	}

	tok_str: string
	switch what in tok.what {
	case Keyword:
		tok_str = fmt.tprintf("'%s'", lexer.KEYWORD_STRINGS[what])
	case Punctuation:
		tok_str = fmt.tprintf("'%s'", lexer.PUNCTUATION_STRINGS[what])
	case Identifier:
		tok_str = fmt.tprintf("an identifier: %s", what)
	case Directive:
		tok_str = fmt.tprintf("'\\%s'", what)
	case Numeric:
		tok_str = fmt.tprintf("a number: %s", what.raw)
	case String:
		tok_str = fmt.tprintf("a string: %s", what.raw)
	case Rune:
		tok_str = fmt.tprintf("a rune: %s", what.raw)
	case lexer.Garbage:
		tok_str = fmt.tprintf("garbage: %s", what)
	}

	diagnostics.emit(
		.Syntax_Error,
		tok.span,
		"expected a top-level declaration here but got %s",
		tok_str,
	)
	ps.cur_token += 1

	return nil, true
}

_annotation :: proc(ps: ^Parser_State) -> ^ast.Annotation {
	at, has_at := _match(ps, Punctuation.At)
	if !has_at {
		return nil
	}
	base, ok := _qualname(ps)
	if !ok {
		_error_here(ps, "expected annotation name after the @")
		return nil
	}
	annotation := new(ast.Annotation)
	annotation^ = {
		span = common.merge_spans(at[0].span, base.span),
		base = base,
	}
	return annotation
}
