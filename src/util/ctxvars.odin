package util

Context_Var :: struct {
	var:  any,
	next: ^Context_Var,
}

find_ctx_var_of :: proc($T: typeid) -> ^T {
	cv := cast(^Context_Var)context.user_ptr
	for cv != nil {
		if cv.var.id == T {
			return cast(^T)cv.var.data
		}
		cv = cv.next
	}
	return nil
}
