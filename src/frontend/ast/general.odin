package ast

import "../../common"

Span :: common.Span

Name :: struct {
	span: Span,
	id:   common.Identifier,
}

Qualified_Name :: struct {
	span: Span,
	path: []common.Identifier,
}
