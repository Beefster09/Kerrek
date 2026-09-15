package analysis

import "base:runtime"
import "core:mem"

import "../../common"
import "../ast"
import "../hir"
import "../resolver"


// Translation_State owns only scratch data used while translating AST to HIR.
// Resolver symbols/scopes remain owned by resolver.Resolver, and every node that
// survives translation must be allocated through output.allocator.
Translation_State :: struct {
	symbol_resolver:     ^resolver.Resolver,
	entry_package:       ^resolver.Package,
	output:              ^hir.Translation_Unit,
	hir_items:           HIR_Accumulator,
	symbols_by_id:       map[common.Symbol_ID]resolver.Partial_Symbol,
	pending_bodies:      [dynamic]Pending_Function_Body,
	pending_annotations: [dynamic]Pending_Annotation_Application,
	processing_stack:    [dynamic]resolver.Partial_Symbol, // used to detect and emit diagnostics for dependency cycles
	scratch_arena:       mem.Dynamic_Arena,
	scratch_allocator:   runtime.Allocator,
}

HIR_Accumulator :: struct {
	types:        [dynamic]hir.Type_Definition,
	funcs:        [dynamic]^hir.Func_Definition,
	variables:    [dynamic]^hir.Global_Variable,
	unit_types:   [dynamic]^hir.Unit_Type,
	units:        [dynamic]^hir.Base_Unit,
	capabilities: [dynamic]^hir.Capability,
	annotations:  [dynamic]^hir.Annotation_Def,
}

// It makes sense to resolve all function signatures before translating their bodies
// so we need some basic information to continue our work
Pending_Function_Body :: struct {
	symbol: ^resolver.Function,
}

// Annotation applications are declaration metadata and must be evaluated once
// their definition's signature is known. Retain the application and its file
// until the compile-time expression pass can validate and materialize its args.
Pending_Annotation_Application :: struct {
	ast:        ^ast.Annotation,
	hir:        ^hir.Annotation,
	definition: ^resolver.Annotation,
	file:       ^resolver.File,
}


// Declaration_Context is passed by value as recursive dependency processing
// moves between files and declarations. Keeping it out of Translation_State
// prevents a nested translation from corrupting the caller's current context.
Declaration_Context :: struct {
	translation: ^Translation_State,
	file:        ^resolver.File,
	scope:       ^resolver.Scope, // nil at top level; file is the resolution parent
	function:    ^resolver.Function,
}

// Expected_Value is contextual information supplied by a destination, return
// slot, parameter, or operator. A nil type/unit means that component is not
// constrained; it is distinct from hir.Indeterminate_Unit.No_Unit.
Expected_Value :: struct {
	type: hir.Type,
	unit: hir.Realized_Unit,
}

Expression_Context :: struct {
	using declaration: Declaration_Context,
	expected:          []Expected_Value,
	use:               Expression_Use,
	arity:             Arity_Expectation,
	comptime:          Comptime_Requirement,
}

Expression_Use :: enum {
	Read,
	Place,
	Move_Source,
	Call_Target,
	Discarded,
}

Arity_Expectation :: struct {
	kind:  Arity_Kind,
	count: int,
}

Arity_Kind :: enum {
	Any,
	Exact,
}

Comptime_Requirement :: enum {
	Runtime_Allowed,
	Required,
}


// Compile-time values can retain a flexible type until a surrounding context
// chooses a concrete HIR type. common.Value carries exact numerics and the
// unmaterialized nil/zero sentinels.
Comptime_Value :: struct {
	span:  common.Span,
	value: common.Value,
	type:  Comptime_Type,
	unit:  hir.Realized_Unit,
}

Comptime_Type :: union {
	hir.Type,
	Flexible_Type,
}

Flexible_Type :: struct {
	affinity: Flexible_Affinity,
}

Flexible_Affinity :: enum {
	Nil,
	Unsigned_Integer,
	Integer,
	Decimal,
	Binary_Float,
	Boolean,
	String,
	Rune,
}

// Wrappers keep single- and multi-value results distinct without duplicating
// the HIR's expression unions.
Single_Expression_Result :: struct {
	expr: hir.Single_Value_Expression,
}

Multi_Expression_Result :: struct {
	expr: hir.Multi_Value_Expression,
}

Expression_Result :: union {
	Comptime_Value,
	Single_Expression_Result,
	Multi_Expression_Result,
	Poison_Result,
}

Poison_Result :: struct {
	span:               common.Span,
	diagnostic_emitted: bool,
}


// Flow facts are analysis output rather than part of the HIR tree. They can be
// replaced by CFG-derived facts later without changing Block itself.
Block_Result :: struct {
	block: ^hir.Block,
	flow:  Control_Flow_Facts,
}

Control_Flow_Facts :: struct {
	may_fall_through: bool,
	may_return:       bool,
	may_fail:         bool,
	may_diverge:      bool,
}

Body_Context :: struct {
	using declaration: Declaration_Context,
	hir_function:      ^hir.Func_Definition,
	loop_depth:        int,
}


init_state :: proc(
	state: ^Translation_State,
	res: ^resolver.Resolver,
	entry_package: ^resolver.Package,
	output: ^hir.Translation_Unit,
) {
	assert(state != nil)
	assert(res != nil)
	assert(entry_package != nil)
	assert(output != nil)

	state.symbol_resolver = res
	state.entry_package = entry_package
	state.output = output
	{
		context.allocator = output.allocator
		state.hir_items.types = make([dynamic]hir.Type_Definition)
		state.hir_items.funcs = make([dynamic]^hir.Func_Definition)
		state.hir_items.variables = make([dynamic]^hir.Global_Variable)
		state.hir_items.unit_types = make([dynamic]^hir.Unit_Type)
		state.hir_items.units = make([dynamic]^hir.Base_Unit)
		state.hir_items.capabilities = make([dynamic]^hir.Capability)
		state.hir_items.annotations = make([dynamic]^hir.Annotation_Def)
	}

	mem.dynamic_arena_init(&state.scratch_arena)
	state.scratch_allocator = mem.dynamic_arena_allocator(&state.scratch_arena)
	{
		context.allocator = state.scratch_allocator
		state.symbols_by_id = make(map[common.Symbol_ID]resolver.Partial_Symbol)
		state.pending_bodies = make([dynamic]Pending_Function_Body)
		state.pending_annotations = make([dynamic]Pending_Annotation_Application)
		state.processing_stack = make([dynamic]resolver.Partial_Symbol)
	}
}

// commit_hir_items freezes the declaration collections for validation. No
// declarations may be appended after this point because a later reallocation
// would leave Translation_Unit holding stale slices.
commit_hir_items :: proc(state: ^Translation_State) {
	assert(state != nil)
	assert(state.output != nil)

	state.output.types = state.hir_items.types[:]
	state.output.funcs = state.hir_items.funcs[:]
	state.output.variables = state.hir_items.variables[:]
	state.output.unit_types = state.hir_items.unit_types[:]
	state.output.units = state.hir_items.units[:]
	state.output.capabilities = state.hir_items.capabilities[:]
	state.output.annotations = state.hir_items.annotations[:]
}

destroy_state :: proc(state: ^Translation_State) {
	if state == nil {
		return
	}
	mem.dynamic_arena_destroy(&state.scratch_arena)
	state^ = {}
}
