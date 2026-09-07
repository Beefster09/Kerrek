package units

import "core:fmt"
import "core:io"

import "../../common"

_compound_unit_names: map[common.Symbol_ID]common.Identifier

register_unit_name :: proc(id: common.Symbol_ID, name: common.Identifier) {
	_compound_unit_names[id] = name
}

Compound_Unit :: union #no_nil {
	Inline_Compound_Unit,
	Heap_Compound_Unit,
}

#assert(size_of(Heap_Compound_Unit) <= 32)
Heap_Compound_Unit :: struct {
	components: []Unit_Component,
	absolute:   bool,
}

#assert(size_of(Inline_Compound_Unit) <= 32)
MAX_INLINE_UNITS :: 4
Inline_Compound_Unit :: struct {
	components: #soa[MAX_INLINE_UNITS]Unit_Component, // soa to pack better
	count:      u8,
	absolute:   bool,
}

Unit_Component :: struct {
	unit: common.Symbol_ID,
	exp:  Small_Rat,
}

num_components :: proc(unit: Compound_Unit) -> int {
	switch u in unit {
	case Inline_Compound_Unit:
		return int(u.count)
	case Heap_Compound_Unit:
		return len(u.components)
	}
	panic("unreachable")
}

get_component :: proc(unit: Compound_Unit, #any_int idx: int) -> Unit_Component {
	switch u in unit {
	case Inline_Compound_Unit:
		when !ODIN_NO_BOUNDS_CHECK {
			assert(idx >= 0 && idx < int(u.count))
		}
		return u.components[idx]
	case Heap_Compound_Unit:
		return u.components[idx]
	}
	panic("unreachable")
}


@(rodata)
SUPERSCRIPT_DIGITS := [10]rune{'⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'}
SUPERSCRIPT_NEGATIVE :: '⁻'

fmt_compound_unit :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Compound_Unit)
	switch verb {
	case 'v':
		fmt.fmt_enum(fi, arg, verb)
	case 's':
		unit := (cast(^Compound_Unit)arg.data)^
		for i in 0 ..< num_components(unit) {
			if i > 0 {
				io.write_rune(fi.writer, ' ')
			}
			comp := get_component(unit, i)
			comp_name, ok := _compound_unit_names[comp.unit]
			if ok {
				io.write_string(fi.writer, string(comp_name))
			} else {
				io.write_string(fi.writer, "UNIT#")
				io.write_int(fi.writer, int(comp.unit))
			}

			if comp.exp.denominator == 1 {
				sup_digits: [dynamic; 3]rune
				x := abs(i16(comp.exp.numerator))
				for x > 0 {
					append(&sup_digits, SUPERSCRIPT_DIGITS[x % 10])
					x /= 10
				}
				if comp.exp.numerator < 0 {
					io.write_rune(fi.writer, SUPERSCRIPT_NEGATIVE)
				}
				#reverse for digit in sup_digits {
					io.write_rune(fi.writer, digit)
				}
			} else {
				io.write_string(fi.writer, "^(")
				io.write_int(fi.writer, int(comp.exp.numerator))
				io.write_rune(fi.writer, '/')
				io.write_int(fi.writer, int(comp.exp.denominator))
				io.write_rune(fi.writer, ')')
			}
		}
	case:
		return false
	}
	return true
}
