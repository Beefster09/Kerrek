package util

import "core:fmt"
import "core:io"

Interpolator :: struct {
	write: proc(w: io.Writer, data: rawptr),
	data:  rawptr,
}

interpolator :: proc(data: ^$T, write: proc(w: io.Writer, data: ^T)) -> Interpolator {
	return {write, transmute(proc(w: io.Writer, data: rawptr))data}
}

fmt_interpolator :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Interpolator)

	switch verb {
	case 's':
		interp := cast(^Interpolator)arg.data
		interp.write(fi.writer, interp.data)
		return true
	}

	return false
}
