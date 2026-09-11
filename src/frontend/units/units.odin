package units

import "core:fmt"
import "core:io"
import "core:slice"

import "../../common"

_compound_unit_names: map[common.Symbol_ID]common.Identifier

register_unit_name :: proc(id: common.Symbol_ID, name: common.Identifier) {
	_compound_unit_names[id] = name
}

Compound_Unit :: union {
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

Unit_Error :: enum {
	OK,
	Unrepresentable_Exponent,
	Absolute_Relative_Mismatch,
}

num_components :: proc(unit: Compound_Unit) -> int {
	switch u in unit {
	case Inline_Compound_Unit:
		return int(u.count)
	case Heap_Compound_Unit:
		return len(u.components)
	case:
		return 0
	}
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
	case:
		return {0, {0, 1}}
	}
}

is_absolute :: proc(unit: Compound_Unit) -> bool {
	switch u in unit {
	case Inline_Compound_Unit:
		return u.absolute
	case Heap_Compound_Unit:
		return u.absolute
	case:
		return false
	}
}

// arbitrary sort function: order by descending exponent, ascending symbol id
// symbol id should roughly correlate with declaration order
_cmp_components :: proc(a, b: Unit_Component) -> slice.Ordering {
	exp_cmp := cmp_rat(a.exp, b.exp)
	if exp_cmp != .Equal {
		return -exp_cmp
	}

	if a.unit < b.unit {
		return .Less
	}
	if a.unit > b.unit {
		return .Greater
	}

	return .Equal
}

combine_units :: proc(
	a: Compound_Unit,
	a_exp: Small_Rat,
	b: Compound_Unit,
	b_exp: Small_Rat,
) -> (
	result: Compound_Unit,
	err: Unit_Error,
) {
	if is_absolute(a) != is_absolute(b) {
		return nil, .Absolute_Relative_Mismatch
	}

	cmp_out := make([dynamic]Unit_Component, 0, num_components(a) + num_components(b))
	defer if _, is_inline := result.(Inline_Compound_Unit); err != .OK || is_inline {
		delete(cmp_out)
	}

	for cu in ([]Compound_Unit{a, b}) {
		for i in 0 ..< num_components(cu) {
			comp := get_component(cu, i)
			new_exp, ok := mul_rat(comp.exp, a_exp)
			if !ok {
				return nil, .Unrepresentable_Exponent
			}

			found := false
			for &existing in cmp_out {

				if comp.unit == existing.unit {
					existing.exp, ok = add_rat(existing.exp, new_exp)
					if !ok {
						return nil, .Unrepresentable_Exponent
					}
					found = true
					break
				}
			}

			if !found {
				append(&cmp_out, Unit_Component{comp.unit, new_exp})
			}
		}
	}

	slice.sort_by_cmp(cmp_out[:], _cmp_components)

	if len(cmp_out) <= MAX_INLINE_UNITS {
		res := Inline_Compound_Unit {
			count    = u8(len(cmp_out)),
			absolute = is_absolute(a),
		}
		for cmp, i in cmp_out {
			res.components[i] = cmp
		}
		return res, .OK
	} else {
		shrink(&cmp_out)
		return Heap_Compound_Unit{components = cmp_out[:], absolute = is_absolute(a)}, .OK
	}
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
