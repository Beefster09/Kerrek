#+test
package parser

import "../ast"


_test_names_equal :: proc(left, right: ast.Name) -> bool {
	return left.id == right.id
}


_test_qualified_names_equal :: proc(left, right: ast.Qualified_Name) -> bool {
	if len(left.path) != len(right.path) {
		return false
	}
	for name, i in left.path {
		if !_test_names_equal(name, right.path[i]) {
			return false
		}
	}
	return true
}


_test_unit_exponents_equal :: proc(left, right: ast.Unit_Exponent) -> bool {
	switch node in left {
	case ast.Integer_Unit_Exponent:
		other, ok := right.(ast.Integer_Unit_Exponent)
		return ok && node.exp == other.exp
	case ast.Rational_Unit_Exponent:
		other, ok := right.(ast.Rational_Unit_Exponent)
		return ok && node.num == other.num && node.den == other.den
	case nil:
		return right == nil
	}
	return false
}


_test_compound_units_equal :: proc(left, right: ^ast.Compound_Unit) -> bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	if left.is_absolute != right.is_absolute || len(left.components) != len(right.components) {
		return false
	}
	for component, i in left.components {
		other := right.components[i]
		if !_test_qualified_names_equal(component.base, other.base) ||
		   !_test_unit_exponents_equal(component.exponent, other.exponent) {
			return false
		}
	}
	return true
}


_test_declared_units_equal :: proc(left, right: ast.Declared_Unit) -> bool {
	switch node in left {
	case ^ast.No_Unit:
		_, ok := right.(^ast.No_Unit)
		return ok
	case ^ast.Inferred_Unit:
		_, ok := right.(^ast.Inferred_Unit)
		return ok
	case ^ast.Flexible_Unit:
		_, ok := right.(^ast.Flexible_Unit)
		return ok
	case ^ast.Compound_Unit:
		other, ok := right.(^ast.Compound_Unit)
		return ok && _test_compound_units_equal(node, other)
	case nil:
		return right == nil
	}
	return false
}


_test_arguments_equal :: proc(left, right: []ast.Argument) -> bool {
	if len(left) != len(right) {
		return false
	}
	for arg, i in left {
		other := right[i]
		if (arg.name == nil) != (other.name == nil) {
			return false
		}
		if arg.name != nil && !_test_names_equal(arg.name.?, other.name.?) {
			return false
		}
		if !_test_expressions_equal(arg.expr, other.expr) {
			return false
		}
	}
	return true
}


_test_types_equal :: proc(left, right: ast.Type_Expression) -> bool {
	switch node in left {
	case ^ast.Simple_Type:
		other, ok := right.(^ast.Simple_Type)
		return ok && _test_qualified_names_equal(node.type, other.type)
	case ^ast.Type_With_Args:
		other, ok := right.(^ast.Type_With_Args)
		return ok &&
		       _test_qualified_names_equal(node.base, other.base) &&
		       _test_arguments_equal(node.args, other.args)
	case ^ast.Generic_Type:
		other, ok := right.(^ast.Generic_Type)
		return ok &&
		       _test_names_equal(node.name, other.name) &&
		       _test_types_equal(node.bound, other.bound)
	case ^ast.Optional_Type:
		other, ok := right.(^ast.Optional_Type)
		return ok && _test_types_equal(node.base, other.base)
	case ^ast.Pointer_Type:
		other, ok := right.(^ast.Pointer_Type)
		return ok &&
		       node.ownership == other.ownership &&
		       _test_types_equal(node.to, other.to)
	case ^ast.Type_With_Tags:
		other, ok := right.(^ast.Type_With_Tags)
		if !ok || !_test_types_equal(node.base, other.base) || len(node.tags) != len(other.tags) {
			return false
		}
		for tag, i in node.tags {
			if !_test_qualified_names_equal(tag, other.tags[i]) {
				return false
			}
		}
		return true
	case nil:
		return right == nil
	}
	return false
}


_test_expressions_equal :: proc(left, right: ast.Expression) -> bool {
	switch node in left {
	case ^ast.Name_Expr:
		other, ok := right.(^ast.Name_Expr)
		return ok && _test_names_equal(node.name, other.name)
	case ^ast.Placeholder_Expr:
		_, ok := right.(^ast.Placeholder_Expr)
		return ok
	case ^ast.FieldAccess_Expr:
		other, ok := right.(^ast.FieldAccess_Expr)
		return ok &&
		       _test_expressions_equal(node.base, other.base) &&
		       _test_names_equal(node.field, other.field)
	case ^ast.Scalar_Literal_Expr:
		other, ok := right.(^ast.Scalar_Literal_Expr)
		return ok &&
		       node.value == other.value &&
		       node.format == other.format &&
		       node.digits == other.digits &&
		       node.scale == other.scale &&
		       _test_compound_units_equal(node.unit, other.unit)
	case ^ast.Simple_Literal_Expr:
		other, ok := right.(^ast.Simple_Literal_Expr)
		return ok && node.value == other.value
	case ^ast.Typed_Zero_Expr:
		other, ok := right.(^ast.Typed_Zero_Expr)
		return ok && _test_types_equal(node.type, other.type)
	case ^ast.Implicit_Enum_Expr:
		other, ok := right.(^ast.Implicit_Enum_Expr)
		return ok &&
		       _test_names_equal(node.name, other.name) &&
		       _test_expressions_equal(node.payload, other.payload)
	case ^ast.Move_Expr:
		other, ok := right.(^ast.Move_Expr)
		return ok && _test_expressions_equal(node.expr, other.expr)
	case ^ast.Binop_Expr:
		other, ok := right.(^ast.Binop_Expr)
		return ok &&
		       node.op == other.op &&
		       _test_expressions_equal(node.lhs, other.lhs) &&
		       _test_expressions_equal(node.rhs, other.rhs)
	case ^ast.Unary_Expr:
		other, ok := right.(^ast.Unary_Expr)
		return ok && node.op == other.op && _test_expressions_equal(node.expr, other.expr)
	case ^ast.Address_Of_Expr:
		other, ok := right.(^ast.Address_Of_Expr)
		return ok && _test_expressions_equal(node.expr, other.expr)
	case ^ast.Dereference_Expr:
		other, ok := right.(^ast.Dereference_Expr)
		return ok && _test_expressions_equal(node.expr, other.expr)
	case ^ast.Cast_Expr:
		other, ok := right.(^ast.Cast_Expr)
		return ok &&
		       _test_expressions_equal(node.expr, other.expr) &&
		       _test_types_equal(node.to, other.to)
	case ^ast.Unit_Conversion_Expr:
		other, ok := right.(^ast.Unit_Conversion_Expr)
		return ok &&
		       _test_expressions_equal(node.expr, other.expr) &&
		       _test_compound_units_equal(node.to, other.to)
	case ^ast.Unit_Reinterpret_Expr:
		other, ok := right.(^ast.Unit_Reinterpret_Expr)
		return ok &&
		       _test_expressions_equal(node.expr, other.expr) &&
		       _test_declared_units_equal(node.new_unit, other.new_unit)
	case ^ast.Index_Expr:
		other, ok := right.(^ast.Index_Expr)
		return ok &&
		       _test_expressions_equal(node.collection, other.collection) &&
		       _test_arguments_equal(node.args, other.args)
	case ^ast.Callish_Expr:
		other, ok := right.(^ast.Callish_Expr)
		return ok &&
		       _test_expressions_equal(node.callee, other.callee) &&
		       _test_arguments_equal(node.args, other.args)
	case ^ast.Type_Expr_Expr:
		other, ok := right.(^ast.Type_Expr_Expr)
		if !ok || node.type == nil || other.type == nil {
			return ok && node.type == nil && other.type == nil
		}
		return _test_types_equal(node.type^, other.type^)
	case ^ast.Unit_Expr:
		other, ok := right.(^ast.Unit_Expr)
		return ok && _test_compound_units_equal(node.unit, other.unit)
	case nil:
		return right == nil
	}
	return false
}
