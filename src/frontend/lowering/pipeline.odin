package lowering


import "../hir"
import "../mir"

hir_to_mir :: proc(h: ^hir.Module) -> ^mir.Module {
	for type in h.types {
		lower_type_def(type)
		// but what about other composed types?
	}
	for var in h.variables {
		// TODO
	}
	for func in h.funcs {
		lower_func(func)
	}
	return nil
}
