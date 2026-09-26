package units

import "core:fmt"
import "core:io"
import "core:slice"

import "../../common"

Compound_Unit :: union {
	Inline_Compound_Unit,
	Heap_Compound_Unit,
}

#assert(size_of(Heap_Compound_Unit) <= 32)
Heap_Compound_Unit :: struct {
	components: []Component,
}

#assert(size_of(Inline_Compound_Unit) <= 32)
MAX_INLINE_UNITS :: 5
Inline_Compound_Unit :: struct {
	comp_base: [MAX_INLINE_UNITS]common.Symbol_ID,
	comp_exp:  [MAX_INLINE_UNITS]Small_Rat,
	count:     u16,
}

Component :: struct {
	unit: common.Symbol_ID,
	exp:  Small_Rat,
}

Builder :: struct {
	components: [dynamic]Component,
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

get_component :: proc(unit: Compound_Unit, #any_int idx: int) -> Component {
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

builder_init :: proc(b: ^Builder, allocator := context.temp_allocator) {
	b.components = make([dynamic]Component, allocator)
}

builder_destroy :: proc(b: ^Builder) {
	delete(b.components)
}

builder_add :: proc {
	builder_add_base_unit,
	builder_add_compound_unit,
}

builder_add_base_unit :: proc(
	b: ^Builder,
	unit: common.Symbol_ID,
	exp: Small_Rat = RAT_ONE,
) -> Unit_Error {
	for &existing, i in b.components {
		if unit == existing.unit {
			ok: bool
			existing.exp, ok = rat_add(existing.exp, exp)
			if !ok {
				return .Unrepresentable_Exponent
			}

			if eq(existing.exp, RAT_ZERO) {
				unordered_remove(&b.components, i)
			}
			return .OK
		}
	}

	append(&b.components, Component{unit, exp})
	return .OK
}

builder_add_compound_unit :: proc(
	b: ^Builder,
	unit: Compound_Unit,
	exp: Small_Rat = RAT_ONE,
) -> Unit_Error {
	for i in 0 ..< num_components(unit) {
		comp := get_component(unit, i)
		new_exp, ok := rat_mul(comp.exp, exp)
		if !ok {
			return .Unrepresentable_Exponent
		}

		err := builder_add_base_unit(b, comp.unit, comp.exp)
		if err != .OK {
			return err
		}
	}

	return .OK
}

combine_units :: proc(
	unit1: Compound_Unit,
	exp1: Small_Rat,
	unit2: Compound_Unit,
	exp2: Small_Rat,
	allocator := context.allocator,
) -> (
	result: Compound_Unit,
	err: Unit_Error,
) {
	b: Builder
	builder_init(&b, context.temp_allocator)
	defer builder_destroy(&b)

	builder_add(&b, unit1, exp1)
	builder_add(&b, unit2, exp2)

	return to_compound_unit(&b, allocator), .OK
}

// arbitrary sort function: order by descending exponent, ascending symbol id
// symbol id should roughly correlate with declaration order
_cmp_components :: proc(a, b: Component) -> slice.Ordering {
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

// creates a compound unit, inline if possible
// sorts the components and clones the slice with the given allocator if necessary
to_compound_unit :: proc(builder: ^Builder, allocator := context.allocator) -> Compound_Unit {
	slice.sort_by_cmp(builder.components[:], _cmp_components)

	if len(builder.components) <= MAX_INLINE_UNITS {
		res := Inline_Compound_Unit {
			count = u16(len(builder.components)),
		}
		for cmp, i in builder.components {
			res.comp_base[i] = cmp.unit
			res.comp_exp[i] = cmp.exp
		}
		return res
	} else {
		return Heap_Compound_Unit{components = slice.clone(builder.components[:], allocator)}
	}
}

base_unit :: proc(unit_id: common.Symbol_ID) -> Compound_Unit {
	unit: Inline_Compound_Unit
	unit.comp_base[0] = unit_id
	unit.comp_exp[0] = {
		n = 1,
		d = 0,
	}
	unit.count = 1
	return unit
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

write_compound_unit :: proc(
	w: io.Writer,
	unit: Compound_Unit,
	get_unit_name: proc(data: ^$D, id: common.Symbol_ID) -> (string, bool),
	get_unit_name_data: ^D,
) {
	for i in 0 ..< num_components(unit) {
		if i > 0 {
			io.write_rune(w, ' ')
		}

		comp := get_component(unit, i)

		if comp_name, ok := get_unit_name(get_unit_name_data, comp.unit); ok {
			io.write_string(w, string(comp_name))
		} else {
			io.write_string(w, "UNIT#")
			io.write_int(w, int(comp.unit))
		}

		if comp.exp.d == 0 {
			sup_digits: [dynamic; 4]rune
			x := abs(i16(comp.exp.n))
			for x > 0 {
				append(&sup_digits, SUPERSCRIPT_DIGITS[x % 10])
				x /= 10
			}
			if comp.exp.n < 0 {
				io.write_rune(w, SUPERSCRIPT_NEGATIVE)
			}
			#reverse for digit in sup_digits {
				io.write_rune(w, digit)
			}
		} else {
			io.write_string(w, "^(")
			io.write_int(w, int(comp.exp.n))
			io.write_rune(w, '/')
			io.write_int(w, int(comp.exp.d + 1))
			io.write_rune(w, ')')
		}
	}
}
