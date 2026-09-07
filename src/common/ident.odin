package common

import "core:mem"
import "core:strings"

Identifier :: distinct string
Symbol_ID :: distinct u32

ident_intern: strings.Intern
_intern_arena: mem.Dynamic_Arena
