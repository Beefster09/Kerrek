#+test
package analysis

import "core:testing"

import "../../common/exact"
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
test_implicit_conversions_preserve_direction :: proc(t: ^testing.T) {
	int32 := hir.Type(hir.Primitive_Type.Int32)
	int64 := hir.Type(hir.Primitive_Type.Int64)

	array32 := hir.Type(&hir.Fixed_Array_Type{elem = int32, shape = []int{1, 2}})
	array64 := hir.Type(&hir.Fixed_Array_Type{elem = int64, shape = []int{1, 2}})
	optional32 := hir.Type(&hir.Optional_Type{base = int32})
	optional64 := hir.Type(&hir.Optional_Type{base = int64})
	tagged32 := hir.Type(&hir.Tagged_Type{base = int32})
	tagged64 := hir.Type(&hir.Tagged_Type{base = int64})
	scalar_array32 := hir.Type(&hir.Fixed_Array_Type{elem = int32, shape = []int{1}})
	scalar_array64 := hir.Type(&hir.Fixed_Array_Type{elem = int64, shape = []int{1}})

	cases := []struct {
		name:        string,
		destination: hir.Type,
		source:      hir.Type,
		expected:    bool,
	} {
		{"widen fixed array elements", array64, array32, true},
		{"reject narrowing fixed array elements", array32, array64, false},
		{"widen optional base", optional64, optional32, true},
		{"reject narrowing optional base", optional32, optional64, false},
		{"unwrap widened tagged base", int64, tagged32, true},
		{"reject narrowing tagged base", int32, tagged64, false},
		{"widen scalar array element", int64, scalar_array32, true},
		{"reject narrowing scalar array element", int32, scalar_array64, false},
	}

	for tc in cases {
		actual := _type_implicitly_converts(tc.destination, tc.source)
		testing.expectf(t, actual == tc.expected, "%s: expected %v, got %v", tc.name, tc.expected, actual)
	}
}


@(test)
test_can_materialize_numeric_values :: proc(t: ^testing.T) {
	flex_integer := Comptime_Type(Flexible_Type{affinity = .Integer})
	flex_decimal := Comptime_Type(Flexible_Type{affinity = .Decimal})

	cases := []struct {
		name:     string,
		target:   hir.Type,
		value:    exact.Rat,
		type:     Comptime_Type,
		expected: bool,
	} {
		{"Int8 minimum", hir.Primitive_Type.Int8, {-128, 1}, flex_integer, true},
		{"Int8 maximum", hir.Primitive_Type.Int8, {127, 1}, flex_integer, true},
		{"below Int8", hir.Primitive_Type.Int8, {-129, 1}, flex_integer, false},
		{"above Int8", hir.Primitive_Type.Int8, {128, 1}, flex_integer, false},
		{"UInt8 maximum", hir.Primitive_Type.UInt8, {255, 1}, flex_integer, true},
		{"negative UInt8", hir.Primitive_Type.UInt8, {-1, 1}, flex_integer, false},
		{"above UInt8", hir.Primitive_Type.UInt8, {256, 1}, flex_integer, false},
		{"Byte maximum", hir.Primitive_Type.Byte, {255, 1}, flex_integer, true},
		{"above Byte", hir.Primitive_Type.Byte, {256, 1}, flex_integer, false},
		{"fractional integer", hir.Primitive_Type.Int64, {3, 2}, flex_decimal, false},
		{"reduced integer", hir.Primitive_Type.Int8, {254, 2}, flex_integer, true},
		{"Binary16 maximum", hir.Primitive_Type.Bin16, {65504, 1}, flex_integer, true},
		{"above Binary16", hir.Primitive_Type.Bin16, {65505, 1}, flex_integer, false},
		{"Decimal boundary", hir.Fixed_Decimal{digits = 3, scale = 2}, {999, 100}, flex_decimal, true},
		{"Decimal overflow", hir.Fixed_Decimal{digits = 3, scale = 2}, {10, 1}, flex_decimal, false},
		{"Decimal excess scale", hir.Fixed_Decimal{digits = 3, scale = 2}, {1, 1000}, flex_decimal, false},
		{
			"typed narrowing remains explicit",
			hir.Primitive_Type.Int8,
			{1, 1},
			hir.Type(hir.Primitive_Type.Int64),
			false,
		},
	}

	for tc in cases {
		value := Comptime_Value {
			value = tc.value,
			type  = tc.type,
			unit  = hir.Indeterminate_Unit.No_Unit,
		}
		actual := can_materialize_value(tc.target, value)
		testing.expectf(t, actual == tc.expected, "%s: expected %v, got %v", tc.name, tc.expected, actual)
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
