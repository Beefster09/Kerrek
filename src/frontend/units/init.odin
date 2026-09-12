package units

import "core:fmt"

import "../../common"

initialize :: proc() {
	_compound_unit_names = make(map[common.Symbol_ID]common.Identifier)
	fmt.register_user_formatter(Compound_Unit, fmt_compound_unit)
	fmt.register_user_formatter(Small_Rat, fmt_rat)
}
