package mir

import "base:runtime"
import "core:fmt"
import "core:io"

import "../../common"


dump_blocks :: proc(w: io.Writer, blocks: []Block) {
	for block in blocks {
		dump_block(w, block)
	}
}

dump_block :: proc(w: io.Writer, block: Block) {
	dump_block_label(w, block.id)
	io.write_string(w, ":\n")
	dump_instructions(w, block.ops)
	io.write_rune(w, '\t')
	dump_terminator(w, block.end)
	io.write_rune(w, '\n')
}

dump_instructions :: proc(w: io.Writer, instructions: []Instruction) {
	for instruction in instructions {
		io.write_rune(w, '\t')
		dump_instruction(w, instruction)
		io.write_rune(w, '\n')
	}
}

dump_terminator :: proc(w: io.Writer, terminator: Terminator) {
	switch terminator in terminator {
	case Jump:
		io.write_string(w, "jmp ")
		dump_block_label(w, terminator.next)
	case Branch_Zero:
		io.write_string(w, "brz ")
		dump_operand(w, terminator.value)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.z_branch)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.nz_branch)
	case Branch_Less:
		io.write_string(w, "brlt ")
		dump_operand(w, terminator.lhs)
		io.write_string(w, ", ")
		dump_operand(w, terminator.rhs)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.lt_branch)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.ge_branch)
	case Branch_Equal:
		io.write_string(w, "breq ")
		dump_operand(w, terminator.lhs)
		io.write_string(w, ", ")
		dump_operand(w, terminator.rhs)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.eq_branch)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.ne_branch)
	case Weak_Ptr_Valid:
		io.write_string(w, "brwk ")
		dump_operand(w, terminator.value)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.valid_branch)
		io.write_string(w, ", ")
		dump_block_label(w, terminator.invalid_branch)
	case Switch:
		io.write_string(w, "sw ")
		dump_operand(w, terminator.value)
		for switch_case in terminator.cases {
			io.write_string(w, "\n\t\t")
			dump_constant(w, switch_case.value)
			io.write_string(w, ": ")
			dump_block_label(w, switch_case.branch)
		}
	case Return:
		io.write_string(w, "ret ")
		dump_operand(w, terminator.value)
	case Fail:
		io.write_string(w, "fail ")
		dump_operand(w, terminator.err)
	}
}

dump_block_label :: proc(w: io.Writer, id: Block_ID) {
	io.write_rune(w, 'b')
	io.write_int(w, int(id))
}

dump_instruction :: proc(w: io.Writer, instruction: Instruction) {
	switch instruction in instruction {
	case Set:
		io.write_string(w, "set ")
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.value)
	case Clear:
		io.write_string(w, "clear ")
		dump_writable(w, instruction.dest)
	case Convert:
		io.write_string(w, "conv ")
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.value)
		io.write_string(w, ", ")
		dump_type(w, instruction.type)
	case Alloc:
		io.write_string(w, "alloc ")
		dump_writable(w, instruction.ptr)
		io.write_string(w, ", ")
		dump_operand(w, instruction.size)
	case Free:
		io.write_string(w, "free ")
		dump_writable(w, instruction.ptr)
	case New_RC:
		io.write_string(w, "newrc ")
		dump_writable(w, instruction.ptr)
		io.write_string(w, ", ")
		dump_operand(w, instruction.size)
	case Inc_RC:
		io.write_string(w, "incrc ")
		dump_writable(w, instruction.ptr)
	case Dec_RC:
		io.write_string(w, "decrc ")
		dump_writable(w, instruction.ptr)
	case Derive_Weak:
		io.write_string(w, "drvwk ")
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.ptr)
	case Get_Addr:
		io.write_string(w, "addr ")
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.of)
	case Add:
		io.write_string(w, "add.")
		io.write_string(w, PRIMITIVE_TYPE_NAMES[instruction.mode.type])
		io.write_string(w, OVERFLOW_MODE_MNEMONICS[instruction.mode.overflow])
		io.write_rune(w, ' ')
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.lhs)
		io.write_string(w, ", ")
		dump_operand(w, instruction.rhs)
	case Sub:
		io.write_string(w, "sub.")
		io.write_string(w, PRIMITIVE_TYPE_NAMES[instruction.mode.type])
		io.write_string(w, OVERFLOW_MODE_MNEMONICS[instruction.mode.overflow])
		io.write_rune(w, ' ')
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.lhs)
		io.write_string(w, ", ")
		dump_operand(w, instruction.rhs)
	case Mul:
		io.write_string(w, "mul.")
		io.write_string(w, PRIMITIVE_TYPE_NAMES[instruction.mode.type])
		io.write_string(w, OVERFLOW_MODE_MNEMONICS[instruction.mode.overflow])
		io.write_rune(w, ' ')
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.lhs)
		io.write_string(w, ", ")
		dump_operand(w, instruction.rhs)
	case Div:
		io.write_string(w, "div.")
		io.write_string(w, PRIMITIVE_TYPE_NAMES[instruction.mode.type])
		io.write_string(w, OVERFLOW_MODE_MNEMONICS[instruction.mode.overflow])
		io.write_rune(w, ' ')
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.lhs)
		io.write_string(w, ", ")
		dump_operand(w, instruction.rhs)
	case Rem:
		io.write_string(w, "rem.")
		io.write_string(w, PRIMITIVE_TYPE_NAMES[instruction.mode.type])
		io.write_string(w, OVERFLOW_MODE_MNEMONICS[instruction.mode.overflow])
		io.write_rune(w, ' ')
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.lhs)
		io.write_string(w, ", ")
		dump_operand(w, instruction.rhs)
	case Truncate:
		io.write_string(w, "trunc ")
		dump_writable(w, instruction.dest)
		io.write_string(w, ", ")
		dump_operand(w, instruction.value)
	case Call:
		io.write_string(w, "call ")
		dump_writable(w, instruction.dest)
		io.write_string(w, " = function(")
		io.write_uint(w, uint(instruction.func.id))
		io.write_string(w, ", ")
		io.write_string(w, string(instruction.func.name))
		io.write_rune(w, ')')
		for arg in instruction.args {
			io.write_string(w, ", ")
			dump_operand(w, arg)
		}
	case Debug_Marker:
		io.write_string(w, "; dbg")
	}
}

dump_operand :: proc(w: io.Writer, operand: Operand) {
	switch operand in operand {
	case Constant:
		dump_constant(w, operand)
	case Temp:
		dump_temporary(w, operand)
	case Local_Var:
		dump_local(w, operand)
	case Global_Var:
		dump_global(w, operand)
	case Parameter:
		dump_parameter(w, operand)
	case Field_Of:
		dump_primitive_operand(w, operand.base)
		io.write_rune(w, '.')
		io.write_string(w, string(operand.field))
	case Index_Of:
		dump_primitive_operand(w, operand.base)
		io.write_rune(w, '[')
		dump_primitive_operand(w, operand.elem)
		io.write_rune(w, ']')
	case Dereferenced:
		io.write_string(w, "*(")
		dump_primitive_operand(w, operand.base)
		io.write_rune(w, ')')
	}
}

dump_writable :: proc(w: io.Writer, writable: Writable) {
	switch writable in writable {
	case Discard:
		io.write_string(w, "_")
	case New_Temp:
		dump_temporary(w, writable)
	case Local_Var:
		dump_local(w, writable)
	case Global_Var:
		dump_global(w, writable)
	case Field_Of:
		dump_primitive_operand(w, writable.base)
		io.write_rune(w, '.')
		io.write_string(w, string(writable.field))
	case Index_Of:
		dump_primitive_operand(w, writable.base)
		io.write_rune(w, '[')
		dump_primitive_operand(w, writable.elem)
		io.write_rune(w, ']')
	case Dereferenced:
		io.write_string(w, "*(")
		dump_primitive_operand(w, writable.base)
		io.write_rune(w, ')')
	}
}

dump_primitive_operand :: proc(w: io.Writer, operand: Primitive_Operand) {
	switch operand in operand {
	case Constant:
		dump_constant(w, operand)
	case Temp:
		dump_temporary(w, operand)
	case Local_Var:
		dump_local(w, operand)
	case Global_Var:
		dump_global(w, operand)
	case Parameter:
		dump_parameter(w, operand)
	}
}

dump_constant :: proc(w: io.Writer, constant: Constant) {
	switch constant in constant {
	case i256:
		io.write_string(w, "i256(")
		common.write_i256(w, constant)
		io.write_string(w, ")")
	case i128:
		io.write_string(w, "i128(")
		io.write_i128(w, constant)
		io.write_rune(w, ')')
	case i64:
		io.write_string(w, "i64(")
		io.write_i64(w, constant)
		io.write_rune(w, ')')
	case i32:
		io.write_string(w, "i32(")
		io.write_i64(w, i64(constant))
		io.write_rune(w, ')')
	case i16:
		io.write_string(w, "i16(")
		io.write_i64(w, i64(constant))
		io.write_rune(w, ')')
	case i8:
		io.write_string(w, "i8(")
		io.write_i64(w, i64(constant))
		io.write_rune(w, ')')
	case u128:
		io.write_string(w, "u128(")
		io.write_u128(w, constant)
		io.write_rune(w, ')')
	case u64:
		io.write_string(w, "u64(")
		io.write_u64(w, constant)
		io.write_rune(w, ')')
	case u32:
		io.write_string(w, "u32(")
		io.write_u64(w, u64(constant))
		io.write_rune(w, ')')
	case u16:
		io.write_string(w, "u16(")
		io.write_u64(w, u64(constant))
		io.write_rune(w, ')')
	case u8:
		io.write_string(w, "u8(")
		io.write_u64(w, u64(constant))
		io.write_rune(w, ')')
	case f64:
		fmt.wprintf(w, "f64(%g)", constant)
	case f32:
		fmt.wprintf(w, "f32(%g)", constant)
	case f16:
		fmt.wprintf(w, "f16(%g)", constant)
	case bool:
		if constant {
			io.write_string(w, "true")
		} else {
			io.write_string(w, "false")
		}
	case string:
		io.write_string(w, "string(")
		io.write_quoted_string(w, constant)
		io.write_rune(w, ')')
	case nil:
		io.write_string(w, "nil")
	}
}

dump_temporary :: proc(w: io.Writer, temporary: $T) where T == Temp || T == New_Temp {
	io.write_string(w, "t")
	io.write_int(w, int(temporary.id))
}

dump_local :: proc(w: io.Writer, local: Local_Var) {
	io.write_string(w, "l")
	io.write_int(w, int(local.id))
}

dump_global :: proc(w: io.Writer, global: Global_Var) {
	io.write_string(w, "g")
	io.write_int(w, int(global.id))
}

dump_parameter :: proc(w: io.Writer, parameter: Parameter) {
	io.write_string(w, "p")
	io.write_int(w, int(parameter.index))
}
dump_type :: proc(w: io.Writer, type: Type) {
	switch type in type {
	case Primitive_Type:
		io.write_string(w, PRIMITIVE_TYPE_NAMES[type])
	case ^Struct_Type:
		io.write_string(w, "struct(")
		io.write_string(w, string(type.name))
		io.write_rune(w, ')')
	case ^Union_Type:
		io.write_string(w, "union(")
		io.write_string(w, string(type.name))
		io.write_rune(w, ')')
	case ^Array_Type:
		fmt.wprintf(w, "[%d]", type.size)
		dump_type(w, type.elem)
	case ^Pointer_Type:
		io.write_rune(w, '*')
		dump_type(w, type.to)
	}
}
