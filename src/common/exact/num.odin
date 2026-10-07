package exact

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math/big"
import "core:mem"
import "core:strings"

bigint_allocator: runtime.Allocator
_bigint_arena: mem.Dynamic_Arena

// An integer that is an i128 in the general case but promotes to bigint for very large values
Int :: union #no_nil {
	i128,
	^big.Int, // this has to be a pointer so that Int and Rat are simply comparable
	// technically they're not *really* simply comparable, but this keeps things simpler in the parser
}

// an exact value represented as a rational
Rat :: struct {
	numerator:   Int,
	denominator: Int,
}

RAT_ONE := Rat{i128(1), i128(1)}
RAT_ZERO := Rat{i128(0), i128(1)}

Decimal :: struct {
	significand: Int,
	scale:       int,
}

DECIMAL_ONE := Decimal{i128(1), 0}
DECIMAL_ZERO := Decimal{i128(0), 0}

fmt_int :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Int)
	switch verb {
	case 'v':
		write_int(fi.writer, (cast(^Int)arg.data)^)
	case 'd', 'i':
		write_int(fi.writer, (cast(^Int)arg.data)^, 10)
	case 'x':
		write_int(fi.writer, (cast(^Int)arg.data)^, 16)
	case 'o':
		write_int(fi.writer, (cast(^Int)arg.data)^, 8)
	case 'b':
		write_int(fi.writer, (cast(^Int)arg.data)^, 2)
	case:
		return false
	}
	return true
}

fmt_rat :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Rat)
	value := (cast(^Rat)arg.data)^
	switch verb {
	case 'r':
		write_int(fi.writer, value.numerator)
		io.write_rune(fi.writer, '/')
		write_int(fi.writer, value.denominator)
	case 'v':
		write_int(fi.writer, value.numerator)
		if !is_one(value.denominator) {
			io.write_rune(fi.writer, '/')
			write_int(fi.writer, value.denominator)
		}
	case 'd':
		write_int(fi.writer, value.numerator, 10)
		if !is_one(value.denominator) {
			io.write_rune(fi.writer, '/')
			write_int(fi.writer, value.denominator, 10)
		}
	case 'x':
		write_int(fi.writer, value.numerator, 16)
		if !is_one(value.denominator) {
			io.write_rune(fi.writer, '/')
			write_int(fi.writer, value.denominator, 16)
		}
	case 'o':
		write_int(fi.writer, value.numerator, 8)
		if !is_one(value.denominator) {
			io.write_rune(fi.writer, '/')
			write_int(fi.writer, value.denominator, 8)
		}
	case 'b':
		write_int(fi.writer, value.numerator, 2)
		if !is_one(value.denominator) {
			io.write_rune(fi.writer, '/')
			write_int(fi.writer, value.denominator, 2)
		}
	case:
		return false
	}
	return true
}

fmt_decimal :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Decimal)
	switch verb {
	case 'v', 'd':
		write_decimal(fi.writer, (cast(^Decimal)arg.data)^)
	case:
		return false
	}
	return true
}

write_decimal :: proc(w: io.Writer, value: Decimal) {
	if int_is_negative(value.significand) {
		io.write_rune(w, '-')
	}

	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	defer strings.builder_destroy(&builder)
	write_int(strings.to_writer(&builder), int_abs(value.significand, context.temp_allocator))
	digits := strings.to_string(builder)

	if value.scale <= 0 {
		io.write_string(w, digits)
		for _ in 0 ..< -value.scale {
			io.write_rune(w, '0')
		}
	} else if value.scale < len(digits) {
		point := len(digits) - value.scale
		io.write_string(w, digits[:point])
		io.write_rune(w, '.')
		io.write_string(w, digits[point:])
	} else {
		io.write_string(w, "0.")
		for _ in 0 ..< value.scale - len(digits) {
			io.write_rune(w, '0')
		}
		io.write_string(w, digits)
	}
}

STACK_DIGITS :: 500

write_int :: proc(w: io.Writer, value: Int, radix: int = 10) {
	switch i in value {
	case i128:
		io.write_i128(w, i, radix)
	case ^big.Int:
		stack_buf: [STACK_DIGITS]u8
		bytes_needed, err := big.radix_size(i, i8(radix))
		assert(err == nil)
		buf :=
			make([]u8, bytes_needed) if bytes_needed > STACK_DIGITS else stack_buf[:bytes_needed]
		defer if raw_data(buf) != &stack_buf[0] {
			delete(buf)
		}
		written: int
		written, err = big.int_itoa_raw(i, i8(radix), buf, size = bytes_needed)
		assert(err == nil)
		io.write(w, buf[:written])
	}
}
