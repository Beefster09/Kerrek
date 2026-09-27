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

Fixed_Decimal_Conversion_Case :: struct {
	name:        string,
	source:      hir.Fixed_Decimal,
	destination: hir.Fixed_Decimal,
	ok:          bool,
}

Fixed_Decimal_Primitive_Case :: struct {
	name:        string,
	source:      hir.Fixed_Decimal,
	destination: hir.Primitive_Type,
	ok:          bool,
}


@(rodata)
FIXED_DECIMAL_COERCION_CASES := [?]Fixed_Decimal_Coercion_Case {
	{
		"identical types",
		{digits = 1, scale = 0},
		{digits = 1, scale = 0},
		{digits = 1, scale = 0},
		true,
	},
	{
		"wider precision at zero scale",
		{digits = 3, scale = 0},
		{digits = 9, scale = 0},
		{digits = 9, scale = 0},
		true,
	},
	{
		"wider precision at equal positive scale",
		{digits = 3, scale = 2},
		{digits = 7, scale = 2},
		{digits = 7, scale = 2},
		true,
	},
	{
		"wider precision at equal negative scale",
		{digits = 3, scale = -2},
		{digits = 7, scale = -2},
		{digits = 7, scale = -2},
		true,
	},
	{
		"greater scale needs no extra integer digits",
		{digits = 5, scale = 2},
		{digits = 5, scale = 4},
		{digits = 7, scale = 4},
		true,
	},
	{
		"positive and negative scales",
		{digits = 3, scale = -2},
		{digits = 3, scale = 2},
		{digits = 7, scale = 2},
		true,
	},
	{
		"both scales exceed precision",
		{digits = 1, scale = 3},
		{digits = 2, scale = 4},
		{digits = 2, scale = 4},
		true,
	},
	{
		"both scales are negative",
		{digits = 3, scale = -2},
		{digits = 5, scale = -4},
		{digits = 7, scale = -2},
		true,
	},
	{
		"minimum scale",
		{digits = 1, scale = hir.MIN_DECIMAL_SCALE},
		{digits = 2, scale = hir.MIN_DECIMAL_SCALE},
		{digits = 2, scale = hir.MIN_DECIMAL_SCALE},
		true,
	},
	{
		"maximum scale",
		{digits = 1, scale = hir.MAX_DECIMAL_SCALE},
		{digits = 2, scale = hir.MAX_DECIMAL_SCALE},
		{digits = 2, scale = hir.MAX_DECIMAL_SCALE},
		true,
	},
	{
		"result has maximum digits",
		{digits = hir.MAX_DECIMAL_DIGITS - 1, scale = 0},
		{digits = hir.MAX_DECIMAL_DIGITS, scale = 1},
		{digits = hir.MAX_DECIMAL_DIGITS, scale = 1},
		true,
	},
	{
		"one digit beyond maximum",
		{digits = hir.MAX_DECIMAL_DIGITS, scale = 0},
		{digits = hir.MAX_DECIMAL_DIGITS, scale = 1},
		{},
		false,
	},
	{
		"opposite scale limits exceed maximum",
		{digits = 1, scale = hir.MIN_DECIMAL_SCALE},
		{digits = 1, scale = hir.MAX_DECIMAL_SCALE},
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

@(rodata)
FIXED_DECIMAL_CONVERSION_CASES := [?]Fixed_Decimal_Conversion_Case {
	{"identical", {digits = 5, scale = 2}, {digits = 5, scale = 2}, true},
	{"greater scale and precision", {digits = 5, scale = 2}, {digits = 7, scale = 4}, true},
	{
		"greater scale with enough integer digits",
		{digits = 5, scale = 2},
		{digits = 6, scale = 3},
		true,
	},
	{"greater integer capacity", {digits = 5, scale = 2}, {digits = 6, scale = 2}, true},
	{"smaller scale", {digits = 5, scale = 2}, {digits = 5, scale = 1}, false},
	{"insufficient integer capacity", {digits = 5, scale = 2}, {digits = 6, scale = 4}, false},
	{"negative scale to zero", {digits = 3, scale = -2}, {digits = 5, scale = 0}, true},
	{"negative scale widened", {digits = 3, scale = -2}, {digits = 4, scale = -1}, true},
	{
		"negative scale with insufficient range",
		{digits = 3, scale = -2},
		{digits = 3, scale = -1},
		false,
	},
	{"negative scale loses precision", {digits = 3, scale = -2}, {digits = 4, scale = -3}, false},
	{"scale exceeds digits", {digits = 1, scale = 3}, {digits = 2, scale = 4}, true},
	{
		"scale exceeds digits with insufficient range",
		{digits = 2, scale = 3},
		{digits = 2, scale = 4},
		false,
	},
}

@(rodata)
SIGNED_INTEGER_DECIMAL_CAPACITIES := [?]Integer_Primitive_Decimal_Case {
	{.Int128, 38},
	{.Int64, 18},
	{.Int32, 9},
	{.Int16, 4},
	{.Int8, 2},
}

@(rodata)
FIXED_DECIMAL_PRIMITIVE_CASES := [?]Fixed_Decimal_Primitive_Case {
	{"Bin16 positive scale", {digits = 1, scale = 1}, .Bin16, false},
	{"Bin16 exact integer range", {digits = 3, scale = 0}, .Bin16, true},
	{"Bin16 excessive integer range", {digits = 4, scale = 0}, .Bin16, false},
	{"Bin16 exact negative scale", {digits = 1, scale = -3}, .Bin16, true},
	{"Bin16 inexact negative scale", {digits = 2, scale = -2}, .Bin16, false},
	{"Bin32 positive scale", {digits = 1, scale = 1}, .Bin32, false},
	{"Bin32 exact integer range", {digits = 7, scale = 0}, .Bin32, true},
	{"Bin32 excessive integer range", {digits = 8, scale = 0}, .Bin32, false},
	{"Bin32 exact negative scale", {digits = 6, scale = -1}, .Bin32, true},
	{"Bin32 inexact negative scale", {digits = 7, scale = -1}, .Bin32, false},
	{"Bin64 positive scale", {digits = 1, scale = 1}, .Bin64, false},
	{"Bin64 exact integer range", {digits = 15, scale = 0}, .Bin64, true},
	{"Bin64 excessive integer range", {digits = 16, scale = 0}, .Bin64, false},
	{"Bin64 exact negative scale", {digits = 15, scale = -1}, .Bin64, true},
	{"Bin64 inexact negative scale", {digits = 16, scale = -1}, .Bin64, false},
	{
		"Any destination",
		{digits = hir.MAX_DECIMAL_DIGITS, scale = hir.MAX_DECIMAL_SCALE},
		.Any,
		true,
	},
}

@(rodata)
NON_SIGNED_INTEGER_PRIMITIVES := [?]hir.Primitive_Type {
	.UInt128,
	.UInt64,
	.UInt32,
	.UInt16,
	.UInt8,
	.Boolean,
	.String,
	.Rune,
	.Byte,
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


_expect_primitive_to_fixed_decimal_conversion :: proc(
	t: ^testing.T,
	primitive: hir.Primitive_Type,
	destination: hir.Fixed_Decimal,
	expected_ok: bool,
) {
	ok := _type_implicitly_converts(hir.Type(destination), hir.Type(primitive))
	testing.expectf(
		t,
		ok == expected_ok,
		"expected %v to Decimal(%d, %d) conversion success %v, got %v",
		primitive,
		destination.digits,
		destination.scale,
		expected_ok,
		ok,
	)
}


_expect_fixed_decimal_conversion :: proc(t: ^testing.T, tc: Fixed_Decimal_Conversion_Case) {
	ok := _type_implicitly_converts(hir.Type(tc.destination), hir.Type(tc.source))
	testing.expectf(
		t,
		ok == tc.ok,
		"%s: expected Decimal(%d, %d) to Decimal(%d, %d) conversion success %v, got %v",
		tc.name,
		tc.source.digits,
		tc.source.scale,
		tc.destination.digits,
		tc.destination.scale,
		tc.ok,
		ok,
	)
}


_expect_fixed_decimal_to_primitive_conversion :: proc(
	t: ^testing.T,
	name: string,
	source: hir.Fixed_Decimal,
	destination: hir.Primitive_Type,
	expected_ok: bool,
) {
	ok := _type_implicitly_converts(hir.Type(destination), hir.Type(source))
	testing.expectf(
		t,
		ok == expected_ok,
		"%s: expected Decimal(%d, %d) to %v conversion success %v, got %v",
		name,
		source.digits,
		source.scale,
		destination,
		expected_ok,
		ok,
	)
}


@(test)
test_coerce_fixed_decimals :: proc(t: ^testing.T) {
	for tc in FIXED_DECIMAL_COERCION_CASES {
		_expect_fixed_decimal_coercion(t, tc.name, tc.left, tc.right, tc.expected, tc.ok)
		_expect_fixed_decimal_coercion(t, tc.name, tc.right, tc.left, tc.expected, tc.ok)
	}
}


@(test)
test_fixed_decimal_implicit_conversions :: proc(t: ^testing.T) {
	for tc in FIXED_DECIMAL_CONVERSION_CASES {
		_expect_fixed_decimal_conversion(t, tc)
	}

	for tc in SIGNED_INTEGER_DECIMAL_CAPACITIES {
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"exact signed integer capacity",
			{digits = u8(tc.required_digits), scale = 0},
			tc.primitive,
			true,
		)
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"excessive signed integer capacity",
			{digits = u8(tc.required_digits + 1), scale = 0},
			tc.primitive,
			false,
		)
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"exact negative scale capacity",
			{digits = u8(tc.required_digits - 1), scale = -1},
			tc.primitive,
			true,
		)
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"excessive negative scale capacity",
			{digits = u8(tc.required_digits), scale = -1},
			tc.primitive,
			false,
		)
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"positive scale to integer",
			{digits = 1, scale = 1},
			tc.primitive,
			false,
		)
	}

	for tc in FIXED_DECIMAL_PRIMITIVE_CASES {
		_expect_fixed_decimal_to_primitive_conversion(t, tc.name, tc.source, tc.destination, tc.ok)
	}

	for primitive in NON_SIGNED_INTEGER_PRIMITIVES {
		_expect_fixed_decimal_to_primitive_conversion(
			t,
			"non-signed-integer destination",
			{digits = 1, scale = 0},
			primitive,
			false,
		)
	}
}


@(test)
test_primitive_to_fixed_decimal_implicit_conversions :: proc(t: ^testing.T) {
	for tc in INTEGER_PRIMITIVE_DECIMAL_CASES {
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			tc.primitive,
			{digits = u8(tc.required_digits - 1), scale = 0},
			false,
		)
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			tc.primitive,
			{digits = u8(tc.required_digits), scale = 0},
			true,
		)
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			tc.primitive,
			{digits = u8(tc.required_digits + 1), scale = 2},
			false,
		)
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			tc.primitive,
			{digits = u8(tc.required_digits + 2), scale = 2},
			true,
		)
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			tc.primitive,
			{digits = u8(tc.required_digits + 1), scale = -1},
			false,
		)
	}

	for primitive in NON_INTEGER_PRIMITIVES {
		_expect_primitive_to_fixed_decimal_conversion(
			t,
			primitive,
			{digits = hir.MAX_DECIMAL_DIGITS, scale = 0},
			false,
		)
	}
}
