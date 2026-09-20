package units

import "core:fmt"

import "../../common"

initialize :: proc() {
	fmt.register_user_formatter(Small_Rat, fmt_rat)
}
