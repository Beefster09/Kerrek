package lowering

import "base:runtime"
import "core:mem"

import "../../common"
import "../hir"
import "../mir"


hir_to_mir :: proc(h: ^hir.Module) -> mir.Module {
	ctx: Translation_Context
	_init_context(&ctx)
	defer _cleanup_context(&ctx)

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)

	types := make([dynamic]mir.Type, 0, len(h.types))
	vars := make([dynamic]mir.Global_Var_Def, 0, len(h.variables))
	funcs := make([dynamic]mir.Function, 0, len(h.funcs))

	for type in h.types {
		free_all(context.temp_allocator)
		append(&types, lower_type_def(&ctx, type))

		// but what about other composed types such as optionals, pointers, etc?
	}

	for var in h.variables {
		free_all(context.temp_allocator)
		// TODO
	}

	for func in h.funcs {
		free_all(context.temp_allocator)
		append(&funcs, lower_func(&ctx, func))
	}

	shrink(&types)
	shrink(&vars)
	shrink(&funcs)
	return {types = types[:], globals = vars[:], functions = funcs[:]}
}


Translation_Context :: struct {
	type_cache: map[common.Symbol_ID]mir.Type,
	debug:      bool,
	arena:      mem.Dynamic_Arena,
	allocator:  runtime.Allocator,
}

_init_context :: proc(ctx: ^Translation_Context) {
	ctx.type_cache = make(map[common.Symbol_ID]mir.Type)
	mem.dynamic_arena_init(&ctx.arena)
	ctx.allocator = mem.dynamic_arena_allocator(&ctx.arena)
}
_cleanup_context :: proc(ctx: ^Translation_Context) {
	delete(ctx.type_cache)
	mem.dynamic_arena_destroy(&ctx.arena)
	ctx^ = {}
}
