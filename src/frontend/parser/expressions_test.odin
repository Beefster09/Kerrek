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


Expression_Parse_Case :: struct {
	source:   string,
	expected: string,
}

@(rodata)
EXPRESSION_PARSE_CASES := [?]Expression_Parse_Case {
	{"-1 ** 2", "-(1 ** 2)"},
	{"+1 ** -2", "+(1 ** (-2))"},
	{"1 ** 2 ** 3", "(1 ** (2 ** 3))"},
	{"1 ** -2 ** 3", "(1 ** (-(2 ** 3)))"},
	{"-1 * 2", "((-1) * 2)"},
	{"1 * -2 + +3", "((1 * (-2)) + (+3))"},
	{"1 - 2 - 3", "((1 - 2) - 3)"},
	{"1 + 2 * 3 ** 4", "(1 + (2 * (3 ** 4)))"},
	{"1 mod 2 * 3 + 4", "(1 mod ((2 * 3) + 4))"},
	{"not 1 == 2", "(not (1 == 2))"},
	{"not not 1 == 2", "(not (not (1 == 2)))"},
	{"not 1 == 2 and 3 or 4", "(((not (1 == 2)) and 3) or 4)"},
	{"nil + 7", "(nil + 7)"},
	{"zero + zero", "(zero + zero)"},
	{"zero(pkg.types.Number) + 1", "(zero(pkg.types.Number) + 1)"},
	{"zero(pkg.Vector(1, -2))", "zero(pkg.Vector(1, (-2)))"},
	{"true == false", "(true == false)"},
	{"\"left\" + \"right\"", "(\"left\" + \"right\")"},
	{"'a' == 'b'", "('a' == 'b')"},
	{"`🔥` + `🧪_42`", "(`🔥` + `🧪_42`)"},
	{"zero(`📦`.`✨`) + `🙂`", "(zero(`📦`.`✨`) + `🙂`)"},
	{"`🧙‍♂️`(`🔥`, -`❄️`)", "`🧙‍♂️`(`🔥`, (-`❄️`))"},
	{"(1 + 2) as pkg.types.Number", "((1 + 2) as pkg.types.Number)"},
	{"-1 as ?pkg.types.Number~traits.Fast", "((-1) as ?pkg.types.Number~traits.Fast)"},
	{
		"1 + 2 reinterpret unit as #si.Meter per time.Second^2",
		"((1 + 2) reinterpret unit as #si.Meter per time.Second^2)",
	},
	{
		"1 si.Meter per time.Second + 2 si.Meter per time.Second",
		"((1 si.Meter per time.Second) + (2 si.Meter per time.Second))",
	},
	{"-pointer^ ** 2", "-((pointer^) ** 2)"},
	{"function(1, -2 + 3)", "function(1, ((-2) + 3))"},
	{"function(1)(2)", "(function(1))(2)"},
	{
		"1 + 2 * 3 ** -4 ** 5 - 6 // 7 mod 8",
		"(((1 + (2 * (3 ** (-(4 ** 5))))) - (6 // 7)) mod 8)",
	},
	{
		"not 1 + 2 * 3 == 4 ** 5 and 6 or 7",
		"(((not ((1 + (2 * 3)) == (4 ** 5))) and 6) or 7)",
	},
	{
		"1 or 2 and not 3 is_not 4 + 5 * 6",
		"(1 or (2 and (not (3 is_not (4 + (5 * 6))))))",
	},
	{
		"-1 ** 2 ** 3 * 4 + 5 mod 6 - 7",
		"((((-(1 ** (2 ** 3))) * 4) + 5) mod (6 - 7))",
	},
	{
		"1 * 2 mod 3 + 4 * 5 == 6 or not 7 and 8",
		"((((1 * 2) mod (3 + (4 * 5))) == 6) or ((not 7) and 8))",
	},
	{
		"not -1 ** +2 * -3 + +4 == -5 ** 6",
		"(not ((((-(1 ** (+2))) * (-3)) + (+4)) == (-(5 ** 6))))",
	},
	{
		"1 ** 2 * 3 ** 4 // 5 % 6 + 7 - 8 mod 9 and not 10 == 11 or 12",
		"(((((((((1 ** 2) * (3 ** 4)) // 5) % 6) + 7) - 8) mod 9) and (not (10 == 11))) or 12)",
	},
	{
		"nil is_not zero or zero(pkg.Type) == 1 and not false",
		"((nil is_not zero) or ((zero(pkg.Type) == 1) and (not false)))",
	},
	{
		"a ** - -b^^ ** +c^ * d^^ + e^ mod f^^ - g^",
		"((((a ** (-(-(b^^ ** (+c^))))) * d^^) + e^) mod (f^^ - g^))",
	},
	{
		"not a^ == b^^ or c^^^ is d^ and e^^^^ is_not f^^",
		"((not (a^ == b^^)) or ((c^^^ is d^) and (e^^^^ is_not f^^)))",
	},
	{
		"not - + - + pointer^^^^ ** - - target^^^ * + - value^^ == other^^^^ and not not flag^^ or + - - tail^^^^^",
		"(((not ((((-(+(-(+(pointer^^^^ ** (-(-target^^^))))))) * (+(-value^^))) == other^^^^)) and (not (not flag^^))) or (+(-(-tail^^^^^)))))",
	},
}


_Test_Parse_Result :: struct {
	expr:         ast.Expression,
	error_count:  int,
	consumed_all: bool,
}


_test_parse_expression :: proc(source: string, file_id: common.Source_ID) -> _Test_Parse_Result {
	sf := common.Source_File {
		id       = file_id,
		file     = source,
		contents = transmute([]u8)source,
	}
	tokens := lexer.tokenize(&sf)
	ps := Parser_State{tokens = tokens}
	expr := _expr(&ps)
	return {expr, ps.error_count, ps.cur_token == len(tokens)}
}


@(test)
test_expression_parsing :: proc(t: ^testing.T) {
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

	for tc, i in EXPRESSION_PARSE_CASES {
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		{
			context.allocator = mem.dynamic_arena_allocator(&arena)
			actual := _test_parse_expression(tc.source, common.Source_ID(i * 2 + 1))
			expected := _test_parse_expression(tc.expected, common.Source_ID(i * 2 + 2))

			actual_ok := actual.expr != nil && actual.error_count == 0 && actual.consumed_all
			testing.expectf(
				t,
				actual_ok,
				"source expression %q did not parse completely without errors",
				tc.source,
			)
			expected_ok := expected.expr != nil && expected.error_count == 0 && expected.consumed_all
			testing.expectf(
				t,
				expected_ok,
				"fully-parenthesized expectation %q for %q did not parse completely without errors",
				tc.expected,
				tc.source,
			)
			if actual_ok && expected_ok {
				testing.expectf(
					t,
					_test_expressions_equal(actual.expr, expected.expr),
					"expected %q to have the same structure as %q",
					tc.source,
					tc.expected,
				)
			}
		}
		mem.dynamic_arena_destroy(&arena)
	}
}
