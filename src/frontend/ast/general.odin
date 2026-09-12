package ast

import "../../common"

Span :: common.Span
Name :: common.Name

Qualified_Name :: struct {
	span: Span,
	path: []Name,
}
