package ast


Capability_Decl :: struct {
	span:        Span,
	name:        Name,
	annotations: []^Annotation,
}

Capability_Expression :: union {
	^Named_Capability,
	^All_Capabilities,
	^Any_Capabilities,
}

Named_Capability :: struct {
	capability: Qualified_Name,
}

All_Capabilities :: struct {
	span:         Span,
	capabilities: []Capability_Expression,
}

Any_Capabilities :: struct {
	span:         Span,
	capabilities: []Capability_Expression,
}

Fact_Decl :: struct {
	span:        Span,
	name:        Name,
	annotations: []^Annotation,
}
