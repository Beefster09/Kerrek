package common

import "base:runtime"
import "core:mem"
import "core:strings"

Identifier :: distinct string
Symbol_ID :: distinct u32

ident_intern: strings.Intern
_string_arena: mem.Dynamic_Arena
string_allocator: runtime.Allocator
