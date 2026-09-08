package parser

import "../../common"
import "../lexer"

Associativity :: enum {
	None,
	Left,
	Right,
}

_Binop_Precedence :: struct {
	prec:          int,
	associativity: Associativity,
}


BINOPS_PRECEDENCE :: [common.Binary_Op]_Binop_Precedence {
	.Power         = {100, .Right},
	.Multiply      = {80, .Left},
	.True_Divide   = {80, .Left},
	.Floor_Divide  = {80, .Left},
	.Remainder     = {80, .Left},
	.Add           = {60, .Left},
	.Subtract      = {60, .Left},
	.Modulo        = {50, .Left},
	.Is            = {40, .None},
	.Is_Not        = {40, .None},
	.Equal         = {40, .None},
	.Not_Equal     = {40, .None},
	.Greater       = {40, .None},
	.Greater_Equal = {40, .None},
	.Less          = {40, .None},
	.Less_Equal    = {40, .None},
	.And           = {20, .Left},
	.Or            = {10, .Left},
}

UNOP_PRECEDENCE :: [common.Unary_Op]int {
	.Positive = 90,
	.Negate   = 90,
	.Not      = 30,
}

PUNCT_BINOP :: #partial [lexer.Punctuation]common.Binary_Op {
	.DStar   = .Power,
	.Star    = .Multiply,
	.Slash   = .True_Divide,
	.DSlash  = .Floor_Divide,
	.Percent = .Remainder,
	.Plus    = .Add,
	.Minus   = .Subtract,
	.EQ      = .Equal,
	.NE      = .Not_Equal,
	.GT      = .Greater,
	.GE      = .Greater_Equal,
	.LT      = .Less,
	.LE      = .Less_Equal,
}

KW_BINOP :: #partial [lexer.Keyword]common.Binary_Op {
	.Mod    = .Modulo,
	.Is     = .Is,
	.Is_Not = .Is_Not,
	.And    = .And,
	.Or     = .Or,
}

PUNCT_UNOP :: #partial [lexer.Punctuation]common.Unary_Op {
	.Plus  = .Positive,
	.Minus = .Negate,
}

KW_UNOP :: #partial [lexer.Keyword]common.Unary_Op {
	.Not = .Not,
}
