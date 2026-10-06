#+test
package exact

import "core:testing"

Float_16_Conversion_Case :: struct {
	source: string,
	bits:   u16,
}

Float_32_Conversion_Case :: struct {
	source: string,
	bits:   u32,
}

Float_64_Conversion_Case :: struct {
	source: string,
	bits:   u64,
}

@(rodata)
FLOAT_16_CONVERSION_CASES := [?]Float_16_Conversion_Case {
	{"0", 0x0000},
	{"-0", 0x0000},
	{"1", 0x3c00},
	{"-1", 0xbc00},
	{"2", 0x4000},
	{"3", 0x4200},
	{"4", 0x4400},
	{"8", 0x4800},
	{"0.8", 0x3800},
	{"1.4", 0x3d00},
	{"1.8", 0x3e00},
	{"1.002p0", 0x3c00},
	{"1.004p0", 0x3c01},
	{"1.006p0", 0x3c02},
	{"1p-14", 0x0400},
	{"0.ffcp-14", 0x03ff},
	{"0.ffep-14", 0x0400},
	{"1.ffcp-15", 0x0400},
	{"1p-24", 0x0001},
	{"1p-23", 0x0002},
	{"1.8p-24", 0x0002},
	{"-1p-24", 0x8001},
	{"1p-25", 0x0000},
	{"1.8p-25", 0x0001},
	{"-1p-25", 0x8000},
	{"1.ffcp15", 0x7bff},
	{"1.ffdp15", 0x7bff},
	{"1.ffep15", 0x7c00},
	{"1p16", 0x7c00},
	{"ffff", 0x7c00},
	{"-ffff", 0xfc00},
	{"1p64", 0x7c00},
}

@(rodata)
FLOAT_32_CONVERSION_CASES := [?]Float_32_Conversion_Case {
	{"0", 0x00000000},
	{"-0", 0x00000000},
	{"1", 0x3f800000},
	{"-1", 0xbf800000},
	{"2", 0x40000000},
	{"3", 0x40400000},
	{"4", 0x40800000},
	{"8", 0x41000000},
	{"0.8", 0x3f000000},
	{"1.4", 0x3fa00000},
	{"1.8", 0x3fc00000},
	{"1.000001p0", 0x3f800000},
	{"1.000002p0", 0x3f800001},
	{"1.000003p0", 0x3f800002},
	{"1p-126", 0x00800000},
	{"0.fffffep-126", 0x007fffff},
	{"0.ffffffp-126", 0x00800000},
	{"1p-149", 0x00000001},
	{"1p-148", 0x00000002},
	{"1.8p-149", 0x00000002},
	{"-1p-149", 0x80000001},
	{"1p-150", 0x00000000},
	{"1.8p-150", 0x00000001},
	{"-1p-150", 0x80000000},
	{"1.fffffep127", 0x7f7fffff},
	{"1.fffffe8p127", 0x7f7fffff},
	{"1.ffffffp127", 0x7f800000},
	{"1p128", 0x7f800000},
	{"-1p128", 0xff800000},
	{"1p256", 0x7f800000},
	{"-1p256", 0xff800000},
}

@(rodata)
FLOAT_64_CONVERSION_CASES := [?]Float_64_Conversion_Case {
	{"0", 0x0000000000000000},
	{"-0", 0x0000000000000000},
	{"1", 0x3ff0000000000000},
	{"-1", 0xbff0000000000000},
	{"2", 0x4000000000000000},
	{"3", 0x4008000000000000},
	{"4", 0x4010000000000000},
	{"8", 0x4020000000000000},
	{"0.8", 0x3fe0000000000000},
	{"1.4", 0x3ff4000000000000},
	{"1.8", 0x3ff8000000000000},
	{"1.00000000000008p0", 0x3ff0000000000000},
	{"1.0000000000001p0", 0x3ff0000000000001},
	{"1.00000000000018p0", 0x3ff0000000000002},
	{"1p-1022", 0x0010000000000000},
	{"0.fffffffffffffp-1022", 0x000fffffffffffff},
	{"0.fffffffffffff8p-1022", 0x0010000000000000},
	{"1p-1074", 0x0000000000000001},
	{"1p-1073", 0x0000000000000002},
	{"1.8p-1074", 0x0000000000000002},
	{"-1p-1074", 0x8000000000000001},
	{"1p-1075", 0x0000000000000000},
	{"1.8p-1075", 0x0000000000000001},
	{"-1p-1075", 0x8000000000000000},
	{"1.fffffffffffffp1023", 0x7fefffffffffffff},
	{"1.fffffffffffff4p1023", 0x7fefffffffffffff},
	{"1.fffffffffffff8p1023", 0x7ff0000000000000},
	{"1p1024", 0x7ff0000000000000},
	{"-1p1024", 0xfff0000000000000},
	{"1p2048", 0x7ff0000000000000},
	{"-1p2048", 0xfff0000000000000},
}

Rational_Conversion_Case :: struct {
	value:   Rat,
	bits_16: u16,
	bits_32: u32,
	bits_64: u64,
}

RATIONAL_CONVERSION_CASES := [?]Rational_Conversion_Case {
	{{1, 3}, 0x3555, 0x3eaaaaab, 0x3fd5555555555555},
	{{2, 3}, 0x3955, 0x3f2aaaab, 0x3fe5555555555555},
	{{1, 10}, 0x2e66, 0x3dcccccd, 0x3fb999999999999a},
	{{1, 7}, 0x3092, 0x3e124925, 0x3fc2492492492492},
	{{10, 3}, 0x42ab, 0x40555555, 0x400aaaaaaaaaaaab},
	{{-1, 3}, 0xb555, 0xbeaaaaab, 0xbfd5555555555555},
	{{6, 4}, 0x3e00, 0x3fc00000, 0x3ff8000000000000},
	{{1, -2}, 0xb800, 0xbf000000, 0xbfe0000000000000},
	{{-1, -2}, 0x3800, 0x3f000000, 0x3fe0000000000000},
	{{123456789, 10000}, 0x7207, 0x4640e6b7, 0x40c81cd6e631f8a1},
	{{-22, 7}, 0xc249, 0xc0492492, 0xc009249249249249},
	{{32767, 13}, 0x68ec, 0x451d889e, 0x40a3b113b13b13b1},
	{{-65536, 1}, 0xfc00, 0xc7800000, 0xc0f0000000000000},
}

_parse_conversion_source :: proc(t: ^testing.T, source: string) -> Rat {
	value, ok := parse_hexfloat(source)
	testing.expectf(t, ok, "could not parse conversion case %q", source)
	if !ok {
		return RAT_ZERO
	}
	return value
}

_test_float_16_conversion :: proc(t: ^testing.T) {
	for tc in FLOAT_16_CONVERSION_CASES {
		value := _parse_conversion_source(t, tc.source)
		actual := transmute(u16)to_float(value, f16)
		testing.expectf(
			t,
			actual == tc.bits,
			"f16 %q: expected 0x%04x, got 0x%04x",
			tc.source,
			tc.bits,
			actual,
		)
	}
}

_test_float_32_conversion :: proc(t: ^testing.T) {
	for tc in FLOAT_32_CONVERSION_CASES {
		value := _parse_conversion_source(t, tc.source)
		actual := transmute(u32)to_float(value, f32)
		testing.expectf(
			t,
			actual == tc.bits,
			"f32 %q: expected 0x%08x, got 0x%08x",
			tc.source,
			tc.bits,
			actual,
		)
	}
}

_test_float_64_conversion :: proc(t: ^testing.T) {
	for tc in FLOAT_64_CONVERSION_CASES {
		value := _parse_conversion_source(t, tc.source)
		actual := transmute(u64)to_float(value, f64)
		testing.expectf(
			t,
			actual == tc.bits,
			"f64 %q: expected 0x%016x, got 0x%016x",
			tc.source,
			tc.bits,
			actual,
		)
	}
}

_test_rational_representations :: proc(t: ^testing.T) {
	for tc in RATIONAL_CONVERSION_CASES {
		actual_16 := transmute(u16)to_float(tc.value, f16)
		actual_32 := transmute(u32)to_float(tc.value, f32)
		actual_64 := transmute(u64)to_float(tc.value, f64)
		testing.expectf(
			t,
			actual_16 == tc.bits_16,
			"f16 %r: expected 0x%04x, got 0x%04x",
			tc.value,
			tc.bits_16,
			actual_16,
		)
		testing.expectf(
			t,
			actual_32 == tc.bits_32,
			"f32 %r: expected 0x%08x, got 0x%08x",
			tc.value,
			tc.bits_32,
			actual_32,
		)
		testing.expectf(
			t,
			actual_64 == tc.bits_64,
			"f64 %r: expected 0x%016x, got 0x%016x",
			tc.value,
			tc.bits_64,
			actual_64,
		)
	}
}

_test_float_conversion :: proc(t: ^testing.T) {
	_test_float_16_conversion(t)
	_test_float_32_conversion(t)
	_test_float_64_conversion(t)
	_test_rational_representations(t)
}
