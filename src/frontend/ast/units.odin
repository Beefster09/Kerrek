package ast

import "../../common/exact"

Declared_Unit :: union {
	^No_Unit,
	^Inferred_Unit,
	^Flexible_Unit,
	^Compound_Unit,
}

unit_span :: proc(unit: Declared_Unit) -> Span {
	switch unit in unit {
	case ^No_Unit:
		return unit.span
	case ^Inferred_Unit:
		return unit.span
	case ^Flexible_Unit:
		return unit.span
	case ^Compound_Unit:
		return unit.span
	}
	return {}
}

Inferred_Unit :: struct {
	span: Span,
}

No_Unit :: struct {
	span: Span,
}

Flexible_Unit :: struct {
	span: Span,
}

Indeterminate_Unit :: enum {
	Inferred, // omitted; unit is inferred based on context
	No_Unit, // explicit nil unit; prevents participation in expressions with units
	Flexible, // explicit _ unit; always matches the desired unit in expressions
}

Unit_Decl :: struct {
	span:        Span,
	name:        Name,
	conversions: []^Unit_Conversion_Def,
	annotations: []^Annotation,
}

Unit_Alias_Decl :: struct {
	span:        Span,
	name:        Name,
	orig:        ^Compound_Unit,
	annotations: []^Annotation,
}

Unit_Conversion_Def :: struct {
	span:       Span,
	direction:  Conversion_Direction,
	other:      Qualified_Name,
	multiplier: Unit_Conversion_Operand,
	divisor:    Unit_Conversion_Operand,
}

Conversion_Direction :: enum {
	To,
	From,
}

Unit_Conversion_Operand :: union {
	exact.Rat,
	Qualified_Name,
}

Compound_Unit :: struct {
	span:        Span,
	components:  []Unit_Component,
	is_absolute: bool,
}


Unit_Component :: struct {
	span:     Span,
	base:     Qualified_Name,
	exponent: Unit_Exponent,
}

Unit_Exponent :: union {
	Integer_Unit_Exponent,
	Rational_Unit_Exponent,
}

Integer_Unit_Exponent :: struct {
	span: Span,
	exp:  int,
}

Rational_Unit_Exponent :: struct {
	span: Span,
	num:  int,
	den:  int,
}
