package parser

import "base:intrinsics"
import "base:runtime"
import "core:mem"

import "../../common"
import "../ast"
import "../lexer"

Parsing_State :: struct {
	tokens:    []lexer.Token,
	cur_token: int,
}

Parse_Error :: enum {
	OK,
	Syntax_Error, // an unrecoverable syntax error
	Not_Found,
	Cannot_Read,
	Other_Error,
}


parse :: proc(src_path: string) -> (file: ^ast.File, err: Parse_Error) {
	sf, ldsrc_err := common.load_source(src_path)
	switch ldsrc_err {
	case .Not_Found:
		return nil, .Not_Found
	case .Cannot_Read:
		return nil, .Cannot_Read
	case .Other_Error:
		return nil, .Other_Error
	case .OK:
	// nothing to do; continue onward
	}
	defer common.unload_source(sf)

	ps := Parsing_State {
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


_parse :: proc(ps: ^Parsing_State, file: ^ast.File) -> Parse_Error {
	annotations := make([dynamic]^ast.Annotation)

	for ps.cur_token < len(ps.tokens) {
		node_raw, err := _toplevel_item(ps)
		if err != .OK {
			continue
		}
		switch node in node_raw {
		}
	}

	return .OK
}

_attach_annotations :: proc(to: $Node, annotations: []^ast.Annotation) {
	when intrinsics.type_is_union(Node) {
		#panic("TODO")
	} else when intrinsics.type_has_field(Node, "annotations") {
		to.annotations = copy(annotations)
	} else {
		#panic("unsupported type for annotation attachment")
	}

}
