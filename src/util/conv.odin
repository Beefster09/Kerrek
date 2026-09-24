package util

import "base:intrinsics"

extract_pair :: proc(
	a, b: $U,
	$V: typeid,
) -> (
	V,
	V,
	bool,
) where intrinsics.type_is_union(U) &&
	intrinsics.type_is_variant_of(U, V) {
	av, a_ok := a.(V)
	bv, b_ok := b.(V)
	return av, bv, a_ok && b_ok
}

chain_extract :: proc(
	u: $U,
	$V1: typeid,
	$V2: typeid,
) -> (
	V2,
	bool,
) where intrinsics.type_is_union(U) &&
	intrinsics.type_is_variant_of(U, V1) &&
	intrinsics.type_is_union(V1) &&
	intrinsics.type_is_variant_of(V1, V2) {
	if v, ok := u.(V1); ok {
		return v.(V2)
	}
	return {}, false
}
