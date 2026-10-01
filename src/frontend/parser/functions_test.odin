#+test
package parser

import "core:mem"
import "core:strings"
import "core:sync"
import "core:testing"

import "../../common"
import "../ast"
import "../diagnostics"
import "../lexer"


@(test)
test_function_units_are_preserved :: proc(t: ^testing.T) {
	sync.lock(&common.Test_Global_State_Lock)
	defer sync.unlock(&common.Test_Global_State_Lock)
	diagnostics.initialize()
	defer diagnostics.destroy()

	intern_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&intern_arena)
	defer mem.dynamic_arena_destroy(&intern_arena)
	strings.intern_init(
		&common.ident_intern,
		allocator = mem.dynamic_arena_allocator(&intern_arena),
	)
	defer strings.intern_destroy(&common.ident_intern)
	parse_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&parse_arena)
	defer mem.dynamic_arena_destroy(&parse_arena)
	context.allocator = mem.dynamic_arena_allocator(&parse_arena)

	source := "func convert(value: Int64, distance: Int64 | meter) -> Int64 | meter {}"
	sf := common.Source_File {
		id       = 1,
		file     = source,
		contents = transmute([]u8)source,
	}
	tokens := lexer.tokenize(&sf)
	ps := Parser_State{tokens = tokens}
	function := _func_def(&ps)

	testing.expect(t, function != nil)
	if function == nil {
		return
	}
	testing.expect(t, ps.error_count == 0)
	testing.expect(t, ps.cur_token == len(tokens))
	testing.expect(t, len(function.params) == 2)
	testing.expect(t, function.returns != nil)
	if len(function.params) != 2 || function.returns == nil {
		return
	}

	_, param_inferred := function.params[0].unit.(^ast.Inferred_Unit)
	_, param_explicit := function.params[1].unit.(^ast.Compound_Unit)
	_, return_explicit := function.returns.unit.(^ast.Compound_Unit)
	testing.expect(t, param_inferred)
	testing.expect(t, param_explicit)
	testing.expect(t, return_explicit)
}
