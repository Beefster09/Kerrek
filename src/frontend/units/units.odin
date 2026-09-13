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
MAX_INLINE_UNITS :: 5
Inline_Compound_Unit :: struct {
	comp_base: [MAX_INLINE_UNITS]common.Symbol_ID,
	comp_exp:  [MAX_INLINE_UNITS]Small_Rat,
	count:     u8,
	absolute:  bool,
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
		return {u.comp_base[idx], u.comp_exp[idx]}
	case Heap_Compound_Unit:
		return u.components[idx]
	case:
		return {}
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
	exp_cmp := rat_cmp(a.exp, b.exp)
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
	a_is_abs := is_absolute(a)
	if a_is_abs != is_absolute(b) {
		return nil, .Absolute_Relative_Mismatch
	}

	cmp_out := make([dynamic]Unit_Component, 0, num_components(a) + num_components(b))
	defer if _, is_inline := result.(Inline_Compound_Unit); err != .OK || is_inline {
		delete(cmp_out)
	}

	#unroll for x in ([?]struct {
			cu:  Compound_Unit,
			exp: Small_Rat,
		}{{a, a_exp}, {b, b_exp}}) {
		next_component: for i in 0 ..< num_components(x.cu) {
			comp := get_component(x.cu, i)
			new_exp, ok := rat_mul(comp.exp, x.exp)
			if !ok {
				return nil, .Unrepresentable_Exponent
			}

			for &existing, i in cmp_out {

				if comp.unit == existing.unit {
					existing.exp, ok = rat_add(existing.exp, new_exp)
					if !ok {
						return nil, .Unrepresentable_Exponent
					}

					if eq(existing.exp, RAT_ZERO) {
						unordered_remove(&cmp_out, i)
					}
					continue next_component
				}
			}

			append(&cmp_out, Unit_Component{comp.unit, new_exp})
		}
	}
	shrink(&cmp_out)
	return build_compound_unit(cmp_out[:], a_is_abs), .OK
}

// creates a compound unit, inline if possible
// assumes ownership of the given slice and sorts the components
build_compound_unit :: proc(components: []Unit_Component, absolute: bool) -> Compound_Unit {
	slice.sort_by_cmp(components, _cmp_components)

	if len(components) <= MAX_INLINE_UNITS {
		res := Inline_Compound_Unit {
			count    = u8(len(components)),
			absolute = absolute,
		}
		for cmp, i in components {
			res.comp_base[i] = cmp.unit
			res.comp_exp[i] = cmp.exp
		}
		return res
	} else {
		return Heap_Compound_Unit{components = components[:], absolute = absolute}
	}
}

compound_units_equal :: proc(a, b: Compound_Unit) -> bool {
	a_len := num_components(a)
	b_len := num_components(b)

	if a_len != b_len {
		return false
	}

	outer: for i in 0 ..< a_len {
		cmp_a := get_component(a, i)
		for j in 0 ..< b_len {
			cmp_b := get_component(b, j)
			if cmp_a.unit == cmp_b.unit {
				if rat_eq(cmp_a.exp, cmp_b.exp) {
					continue outer
				} else {
					return false
				}
			}
		}

		// matching base unit wasn't found
		return false
	}

	// everything matched
	return true
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

			if comp.exp.d == 0 {
				sup_digits: [dynamic; 4]rune
				x := abs(i16(comp.exp.n))
				for x > 0 {
					append(&sup_digits, SUPERSCRIPT_DIGITS[x % 10])
					x /= 10
				}
				if comp.exp.n < 0 {
					io.write_rune(fi.writer, SUPERSCRIPT_NEGATIVE)
				}
				#reverse for digit in sup_digits {
					io.write_rune(fi.writer, digit)
				}
			} else {
				io.write_string(fi.writer, "^(")
				io.write_int(fi.writer, int(comp.exp.n))
				io.write_rune(fi.writer, '/')
				io.write_int(fi.writer, int(comp.exp.d + 1))
				io.write_rune(fi.writer, ')')
			}
		}
	case:
		return false
	}
	return true
}
