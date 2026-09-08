package common

import "exact"

Value :: union #no_nil {
	Flex_Value,
	exact.Rat,
	string,
	rune,
	byte,
	bool,
}

Flex_Value :: enum {
	Nil,
	Zero,
}

Pointer_Ownership :: enum {
	Borrow,
	Owned,
	Shared,
	Weak,
	Unsafe,
}

Unary_Op :: enum {
	Positive = 1,
	Negate,
	Not,
}

Binary_Op :: enum {
	Add = 1,
	Subtract,
	Multiply,
	True_Divide,
	Floor_Divide,
	Remainder,
	Modulo,
	Power,
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	Is,
	Is_Not,
	And,
	Or,
}

UNARY_OP_STRINGS :: [Unary_Op]string {
	.Positive = "+",
	.Negate   = "-",
	.Not      = "not",
}

BINARY_OP_STRINGS :: [Binary_Op]string {
	.Add           = "+",
	.Subtract      = "-",
	.Multiply      = "*",
	.True_Divide   = "/",
	.Floor_Divide  = "//",
	.Remainder     = "%",
	.Modulo        = "mod",
	.Power         = "**",
	.Equal         = "==",
	.Not_Equal     = "!=",
	.Less          = "<",
	.Less_Equal    = "<=",
	.Greater       = ">",
	.Greater_Equal = ">=",
	.Is            = "is",
	.Is_Not        = "is_not",
	.And           = "and",
	.Or            = "or",
}
