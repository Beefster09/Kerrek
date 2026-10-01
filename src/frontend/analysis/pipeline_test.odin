#+test
package analysis

import "core:sync"
import "core:testing"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


@(test)
test_valid_function_body_preserves_success :: proc(t: ^testing.T) {
	sync.lock(&common.Test_Global_State_Lock)
	defer sync.unlock(&common.Test_Global_State_Lock)
	diagnostics.initialize()
	defer diagnostics.destroy()

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)
	context.allocator = res.allocator
	context.temp_allocator = res.allocator

	pkg := new(resolver.Package, res.allocator)
	pkg.defined_symbols = make(map[common.Identifier]resolver.Symbol, res.allocator)
	file := new(resolver.File, res.allocator)
	file.own_package = pkg
	file.defined_symbols = make([dynamic]resolver.Symbol, res.allocator)
	pkg.files = []^resolver.File{file}
	append(&res.loaded_packages, pkg)

	body := new(ast.Block, res.allocator)
	definition := new(ast.Func_Definition, res.allocator)
	definition.name.id = "main"
	definition.body = body
	function := resolver.new_symbol(&res, resolver.Function, definition.name.id)
	function.ast = definition
	function.defined_in = file
	pkg.defined_symbols[definition.name.id] = function
	append(&file.defined_symbols, function)

	tu, err := build_hir(&res, pkg)
	testing.expect(t, err == .OK)
	testing.expect(t, tu != nil)
	if tu != nil {
		hir.destroy(tu)
		free(tu)
	}
}
