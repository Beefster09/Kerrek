#+test
package analysis

import "core:testing"

import "../hir"


Fixed_Decimal_Coercion_Case :: struct {
	name:     string,
	left:     hir.Fixed_Decimal,
	right:    hir.Fixed_Decimal,
	expected: hir.Fixed_Decimal,
	ok:       bool,
}

Integer_Primitive_Decimal_Case :: struct {
	primitive:       hir.Primitive_Type,
	required_digits: i32,
}


@(rodata)
FIXED_DECIMAL_COERCION_CASES := [?]Fixed_Decimal_Coercion_Case {
	{"identical types", {1, 0}, {1, 0}, {1, 0}, true},
	{"wider precision at zero scale", {3, 0}, {9, 0}, {9, 0}, true},
	{"wider precision at equal positive scale", {3, 2}, {7, 2}, {7, 2}, true},
	{"wider precision at equal negative scale", {3, -2}, {7, -2}, {7, -2}, true},
	{"greater scale needs no extra integer digits", {5, 2}, {5, 4}, {7, 4}, true},
	{"positive and negative scales", {3, -2}, {3, 2}, {7, 2}, true},
	{"both scales exceed precision", {1, 3}, {2, 4}, {2, 4}, true},
	{"both scales are negative", {3, -2}, {5, -4}, {7, -2}, true},
	{
		"minimum scale",
		{1, hir.MIN_DECIMAL_SCALE},
		{2, hir.MIN_DECIMAL_SCALE},
		{2, hir.MIN_DECIMAL_SCALE},
		true,
	},
	{
		"maximum scale",
		{1, hir.MAX_DECIMAL_SCALE},
		{2, hir.MAX_DECIMAL_SCALE},
		{2, hir.MAX_DECIMAL_SCALE},
		true,
	},
	{"result has maximum digits", {999, 0}, {1000, 1}, {hir.MAX_DECIMAL_DIGITS, 1}, true},
	{"one digit beyond maximum", {1000, 0}, {1000, 1}, {}, false},
	{
		"opposite scale limits exceed maximum",
		{1, hir.MIN_DECIMAL_SCALE},
		{1, hir.MAX_DECIMAL_SCALE},
		{},
		false,
	},
}

@(rodata)
INTEGER_PRIMITIVE_DECIMAL_CASES := [?]Integer_Primitive_Decimal_Case {
	{.Int128, 39},
	{.Int64, 19},
	{.Int32, 10},
	{.Int16, 5},
	{.Int8, 3},
	{.UInt128, 39},
	{.UInt64, 20},
	{.UInt32, 10},
	{.UInt16, 5},
	{.UInt8, 3},
}

@(rodata)
NON_INTEGER_PRIMITIVES := [?]hir.Primitive_Type {
	.Bin64,
	.Bin32,
	.Bin16,
	.Boolean,
	.String,
	.Rune,
	.Byte,
	.Any,
	.Opaque,
	.Opaque8,
	.Opaque16,
	.Opaque32,
	.Opaque64,
}


_expect_fixed_decimal_coercion :: proc(
	t: ^testing.T,
	name: string,
	left, right: hir.Fixed_Decimal,
	expected: hir.Fixed_Decimal,
	expected_ok: bool,
) {
	actual, ok := coerce(hir.Type(left), hir.Type(right))
	testing.expectf(t, ok == expected_ok, "%s: expected success %v, got %v", name, expected_ok, ok)
	if !expected_ok {
		testing.expectf(t, actual == nil, "%s: expected failed coercion to return nil", name)
		return
	}
	if !ok {
		return
	}

	actual_type, is_type := actual.(hir.Type)
	testing.expectf(t, is_type, "%s: expected a concrete type", name)
	if !is_type {
		return
	}
	actual_decimal, is_decimal := actual_type.(hir.Fixed_Decimal)
	testing.expectf(t, is_decimal, "%s: expected a fixed decimal result", name)
	if is_decimal {
		testing.expectf(
			t,
			actual_decimal == expected,
			"%s: expected Decimal(%d, %d), got Decimal(%d, %d)",
			name,
			expected.digits,
			expected.scale,
			actual_decimal.digits,
			actual_decimal.scale,
		)
	}
}


_expect_primitive_fixed_decimal_coercion :: proc(
	t: ^testing.T,
	primitive: hir.Primitive_Type,
	destination: hir.Fixed_Decimal,
	expected_ok: bool,
) {
	for primitive_first in ([?]bool{true, false}) {
		actual: Comptime_Type
		ok: bool
		if primitive_first {
			actual, ok = coerce(hir.Type(primitive), hir.Type(destination))
		} else {
			actual, ok = coerce(hir.Type(destination), hir.Type(primitive))
		}

		testing.expectf(
			t,
			ok == expected_ok,
			"expected %v and Decimal(%d, %d) coercion success %v, got %v",
			primitive,
			destination.digits,
			destination.scale,
			expected_ok,
			ok,
		)
		if !expected_ok {
			testing.expectf(t, actual == nil, "expected failed primitive coercion to return nil")
			continue
		}
		if !ok {
			continue
		}

		actual_type, is_type := actual.(hir.Type)
		testing.expectf(t, is_type, "expected primitive coercion to produce a concrete type")
		if !is_type {
			continue
		}
		actual_decimal, is_decimal := actual_type.(hir.Fixed_Decimal)
		testing.expectf(t, is_decimal, "expected primitive coercion to produce a fixed decimal")
		if is_decimal {
			testing.expectf(
				t,
				actual_decimal == destination,
				"expected primitive coercion to preserve destination type",
			)
		}
	}
}


@(test)
test_coerce_fixed_decimals :: proc(t: ^testing.T) {
	for tc in FIXED_DECIMAL_COERCION_CASES {
		_expect_fixed_decimal_coercion(t, tc.name, tc.left, tc.right, tc.expected, tc.ok)
		_expect_fixed_decimal_coercion(t, tc.name, tc.right, tc.left, tc.expected, tc.ok)
	}
}


@(test)
test_coerce_primitive_to_fixed_decimal :: proc(t: ^testing.T) {
	for tc in INTEGER_PRIMITIVE_DECIMAL_CASES {
		_expect_primitive_fixed_decimal_coercion(
			t,
			tc.primitive,
			{tc.required_digits - 1, 0},
			false,
		)
		_expect_primitive_fixed_decimal_coercion(t, tc.primitive, {tc.required_digits, 0}, true)
		_expect_primitive_fixed_decimal_coercion(
			t,
			tc.primitive,
			{tc.required_digits + 1, 2},
			false,
		)
		_expect_primitive_fixed_decimal_coercion(
			t,
			tc.primitive,
			{tc.required_digits + 2, 2},
			true,
		)
		_expect_primitive_fixed_decimal_coercion(
			t,
			tc.primitive,
			{tc.required_digits + 1, -1},
			false,
		)
	}

	for primitive in NON_INTEGER_PRIMITIVES {
		_expect_primitive_fixed_decimal_coercion(t, primitive, {hir.MAX_DECIMAL_DIGITS, 0}, false)
	}
}
