package units

import "../../common"

Compound_Unit :: union #no_nil {
	Inline_Compound_Unit,
	Heap_Compound_Unit,
}

#assert(size_of(Heap_Compound_Unit) <= 32)
Heap_Compound_Unit :: struct {
	components: []Unit_Component,
	absolute:   bool,
}
MAX_INLINE_UNITS :: 4
#assert(size_of(Inline_Compound_Unit) <= 32)
Inline_Compound_Unit :: struct {
	components: #soa[MAX_INLINE_UNITS]Unit_Component, // soa to pack better
	count:      u8,
	absolute:   bool,
}

Unit_Component :: struct {
	unit: common.Symbol_ID,
	exp:  Small_Rat,
}
