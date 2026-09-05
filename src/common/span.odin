package common


Span :: struct {
	file:  Source_ID,
	start: Location,
	end:   Location,
}

Location :: struct {
	offset: u32,
	row:    u16,
	col:    u16,
}

tab_width: u16 = #config(DEFAULT_TAB_WIDTH, 4) // determines how col is counted
