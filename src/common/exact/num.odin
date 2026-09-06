package exact

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math/big"
import "core:mem/virtual"

bigint_allocator: runtime.Allocator
_bigint_arena: virtual.Arena


// an exact value represented as a rational
Rat :: struct {
	numerator:   Int,
	denominator: Int,
}

// An integer that is an i128 in the general case but promotes to bigint for very large values
Int :: union #no_nil {
	i128,
	big.Int,
}


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

STACK_DIGITS :: 500

write_int :: proc(w: io.Writer, value: Int, radix: int = 10) {
	value := value
	switch &i in value {
	case i128:
		io.write_i128(w, i, radix)
	case big.Int:
		stack_buf: [STACK_DIGITS]u8
		bytes_needed, err := big.radix_size(&i, i8(radix))
		buf := make([]u8, bytes_needed) if bytes_needed > STACK_DIGITS else stack_buf[:]
		defer if raw_data(buf) != &stack_buf[0] {
			delete(buf)
		}
		big.int_itoa_raw(&i, i8(radix), buf)
		io.write(w, buf)
	}
}
