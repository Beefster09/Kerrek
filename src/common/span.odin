package common

Source_ID :: distinct u32

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
