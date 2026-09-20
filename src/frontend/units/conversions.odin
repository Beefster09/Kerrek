package units

import "base:runtime"
import "core:slice"
import "core:sync"

import "../../common"
import "../../common/exact"

Conversion_Graph :: struct {
	edges: [dynamic]Conversion_Edge,
	cache: map[[2]common.Symbol_ID]Conversion,
	_lock: sync.Mutex, // protects cache
	state: enum {
		Constructing,
		Complete,
	},
}

Conversion_Edge :: struct {
	span:       common.Span,
	from:       common.Symbol_ID,
	to:         common.Symbol_ID,
	using conv: Conversion,
}

Conversion :: struct {
	ratio:    exact.Rat,
	explicit: bool,
}

init_conversions :: proc(graph: ^Conversion_Graph) {
	assert(graph.edges == nil)
	assert(graph.cache == nil)
	graph^ = {
		edges = make([dynamic]Conversion_Edge),
	}
}

add_conversion :: proc(
	graph: ^Conversion_Graph,
	span: common.Span,
	from, to: common.Symbol_ID,
	ratio: exact.Rat,
	explicit := false,
) {
	sync.lock(&graph._lock)
	defer sync.unlock(&graph._lock)
	assert(!exact.is_zero(ratio.denominator))

	append(
		&graph.edges,
		Conversion_Edge{from = from, to = to, ratio = ratio, explicit = explicit},
		Conversion_Edge {
			from = to,
			to = from,
			ratio = exact.reciprocal(ratio),
			explicit = explicit,
		},
	)
}

destroy_conversions :: proc(graph: ^Conversion_Graph) {
	defer graph^ = {}

	sync.lock(&graph._lock)
	defer sync.unlock(&graph._lock)

	if graph.cache != nil {
		graph.edges.allocator = graph.cache.allocator
		delete(graph.cache)
	}
	delete(graph.edges)
}

freeze_conversion_graph :: proc(graph: ^Conversion_Graph) {
	shrink(&graph.edges)
	slice.sort_by_cmp(graph.edges[:], proc(a, b: Conversion_Edge) -> slice.Ordering {
		if a.from < b.from {
			return .Less
		}
		if a.from > b.from {
			return .Greater
		}

		if a.to < b.to {
			return .Less
		}
		if a.to > b.to {
			return .Greater
		}

		return .Equal
	})
	graph.state = .Complete
	graph.cache = make(map[[2]common.Symbol_ID]Conversion, graph.edges.allocator)
	graph.edges.allocator = runtime.nil_allocator()
}
