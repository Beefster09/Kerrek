package units

import "core:fmt"

initialize :: proc() {
	fmt.register_user_formatter(Small_Rat, fmt_rat)
	fmt.register_user_formatter(Compound_Unit, fmt_compound_unit)
}
