package ast

import "base:intrinsics"
import "core:mem"

import "../../common"

File :: struct {
	source:       ^common.Source_File,
	imports:      []^Import,
	declarations: []Top_Level_Declaration,
	node_arena:   ^mem.Dynamic_Arena,
}

Top_Level_Item :: intrinsics.type_merge(Top_Level_Declaration, union {
		^Import,
		^Annotation,
	})

Top_Level_Declaration :: union {
	^Global_Constant,
	^Global_Variable,
	^Type_Alias,
	^Annotation_Def,
	^Unit_Type_Decl,
	^Unit_Type_Alias_Decl,
	^Unit_Decl,
	^Unit_Alias_Decl,
	^Capability_Decl,
	^Func_Definition,
}

Import :: struct {
	span:        Span,
	collection:  common.Identifier, // empty string = internal import, nonempty = use that collection
	path:        []Import_Path_Element,
	using_names: []Name,
	// how many levels to go up for a relative import:
	// 0 means from current directory
	// 1+ means traverse that many levels up
	// -1 means the path is absolute
	relative_up: int,
	annotations: []^Annotation,
}

Import_Path_Element :: union #no_nil {
	string,
	common.Identifier,
}

Global_Constant :: struct {
	span:        Span,
	name:        Name,
	type:        Type_Expression,
	unit:        Declared_Unit,
	expr:        Expression,
	annotations: []^Annotation,
}

Global_Variable :: struct {
	span:        Span,
	name:        Name,
	type:        Type_Expression,
	unit:        Declared_Unit,
	expr:        Expression,
	annotations: []^Annotation,
}
