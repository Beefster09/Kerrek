package common

import "exact"

Flexible_Value :: union {
	exact.Rat,
	string,
	rune,
	byte,
	bool,
}
