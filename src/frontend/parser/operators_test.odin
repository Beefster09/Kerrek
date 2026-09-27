#+test
package parser

import "core:mem"
import "core:sync"
import "core:testing"

import "../../common"
import "../diagnostics"


Non_Associative_Operator_Case :: struct {
	source:         string,
	expected_start: u32,
	expected_end:   u32,
}

@(rodata)
NON_ASSOCIATIVE_OPERATOR_CASES := [?]Non_Associative_Operator_Case {
	{"1 is 2 is 3", 7, 9},
	{"1 is_not 2 is_not 3", 11, 17},
	{"1 == 2 == 3", 7, 9},
	{"1 != 2 != 3", 7, 9},
	{"1 > 2 > 3", 6, 7},
	{"1 >= 2 >= 3", 7, 9},
	{"1 < 2 < 3", 6, 7},
	{"1 <= 2 <= 3", 7, 9},
	{"1 < 2 == 3", 6, 8},
	{"1 == 2 < 3", 7, 8},
	{"1 + 2 < 3 * 4 <= 5 ** 6", 14, 16},
}


@(test)
test_non_associative_operators_are_syntax_errors :: proc(t: ^testing.T) {
	sync.lock(&common.Test_Global_State_Lock)
	defer sync.unlock(&common.Test_Global_State_Lock)
	diagnostics.initialize()
	defer diagnostics.destroy()

	for tc, i in NON_ASSOCIATIVE_OPERATOR_CASES {
		clear(&diagnostics._current_diagnostics)
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		{
			context.allocator = mem.dynamic_arena_allocator(&arena)
			file_id := common.Source_ID(1000 + i)
			result := _test_parse_expression(tc.source, file_id)
			testing.expectf(
				t,
				result.expr == nil && result.error_count == 1,
				"expected %q to produce exactly one syntax error",
				tc.source,
			)
			testing.expectf(
				t,
				len(diagnostics._current_diagnostics) == 1,
				"expected one diagnostic for %q, got %d",
				tc.source,
				len(diagnostics._current_diagnostics),
			)
			if len(diagnostics._current_diagnostics) == 1 {
				diagnostic := diagnostics._current_diagnostics[0]
				testing.expectf(
					t,
					diagnostic.code == .Syntax_Error,
					"expected a syntax error code for %q, got %v",
					tc.source,
					diagnostic.code,
				)
				testing.expectf(
					t,
					diagnostic.span.file == file_id &&
					diagnostic.span.start.offset == tc.expected_start &&
					diagnostic.span.end.offset == tc.expected_end,
					"unexpected diagnostic span for %q",
					tc.source,
				)
			}
		}
		mem.dynamic_arena_destroy(&arena)
	}
}
