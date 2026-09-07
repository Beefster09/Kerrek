package ast

Func_Definition :: struct {
	span:       Span,
	name:       Name,
	params:     []^Formal_Parameter,
	returns:    []^Func_Return,
	error_type: Type_Expression,
	fallible:   bool,
	requires:   Capability_Expression,
	body:       ^Block,
}

Formal_Parameter :: struct {
	span:    Span,
	name:    Name,
	type:    Type_Expression,
	unit:    Declared_Unit,
	default: Expression,
}

Func_Return :: struct {
	span: Span,
	name: Maybe(Name),
	type: Type_Expression,
	unit: Declared_Unit,
}

Func_Overload_Group :: struct {
	span:      Span,
	name:      Name,
	overloads: []Qualified_Name,
}

Annotation :: struct {
	span: Span,
	base: Qualified_Name,
	args: []Argument,
}

Annotation_Def :: struct {
	span:        Span,
	name:        Name,
	args:        []^Formal_Parameter,
	annotations: []^Annotation,
}

Argument :: struct {
	span: Span,
	name: Maybe(Name),
	expr: Expression,
}
