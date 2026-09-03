import builtins
from enum import Enum, auto
from typing import NamedTuple, TextIO

from frontend import hir, mir
from frontend.types import PrimitiveType


class CReturnConvention(Enum):
    Void = auto()
    Single = auto()
    IsOK = auto()
    Struct = auto()
    TaggedUnion = auto()


class CReturnStyle(NamedTuple):
    convention: CReturnConvention
    ctypename: str


def emit_function_proto(out: TextIO, func: mir.Function):
    ret_style = return_style(func)

    if ret_style.convention is CReturnConvention.Struct:
        print("typedef struct {", file=out)
        for i, ret in enumerate(func.returns):
            print(f"\t{type_name(ret)} r{i};", file=out)
        print(f"}} {ret_style.ctypename};", file=out)
    elif ret_style.convention is CReturnConvention.TaggedUnion:
        assert func.error
        print("typedef struct {", file=out)
        print("\tbool ok;", file=out)
        print("\tunion {", file=out)
        print("\t\tstruct {", file=out)
        for i, ret in enumerate(func.returns):
            print(f"\t\t\t{type_name(ret)} r{i};", file=out)
        print("\t\t} rets;", file=out)
        print(f"\t\t{type_name(func.error)} err;", file=out)
        print("\t};", file=out)
        print(f"}} {ret_style.ctypename};", file=out)

    _emit_func_params(out, func, ret_style)
    print(";", file=out)


def emit_function(out: TextIO, func: mir.Function):
    ret_style = return_style(func)
    _emit_func_params(out, func, ret_style)
    print(" {", file=out)

    for var in func.locals:
        print(f"\t{type_name(var.type)} {_value(var)};", file=out)

    for block in func.blocks:
        print(f"block{block.id}:", file=out)

        for op in block.ops:
            _emit_op(out, op)

        _emit_terminator(out, block.end, ret_style)

    print("}", file=out)


def _emit_func_params(out: TextIO, func: mir.Function, ret_style: CReturnStyle):
    print(ret_style.ctypename, end=" ", file=out)
    if func.no_mangle:
        print(func.name, end="(", file=out)
    else:
        print(f"krkFunction{func.id}", end="(", file=out)

    if not func.params:
        print("void", end="", file=out)

    for param in func.params:
        if param.index > 0:
            print(", ", end="", file=out)
        print(type_name(param.type), _value(param), end="", file=out)

    print(")", end="", file=out)


def _emit_op(out: TextIO, op: mir.Operation):
    match op:
        case mir.Add(dest, lhs, rhs):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            print(_value(dest), "=", _value(lhs), "+", _value(rhs), end=";\n", file=out)

        case mir.Sub(dest, lhs, rhs):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            print(_value(dest), "=", _value(lhs), "-", _value(rhs), end=";\n", file=out)

        case mir.Mul(dest, lhs, rhs):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            print(_value(dest), "=", _value(lhs), "*", _value(rhs), end=";\n", file=out)

        case mir.Div(dest, lhs, rhs):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            print(_value(dest), "=", _value(lhs), "/", _value(rhs), end=";\n", file=out)

        case mir.Rem(dest, lhs, rhs):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            # FIXME: this is only correct for integers
            print(_value(dest), "=", _value(lhs), "%", _value(rhs), end=";\n", file=out)

        case mir.Set(dest, src):
            print("\t", end="", file=out)
            print(_value(dest), "=", _value(src), end=";\n", file=out)

        case mir.Convert(dest, src, type):
            print("\t", end="", file=out)
            if isinstance(dest, mir.Temporary):
                print(type_name(dest.type), end=" ", file=out)
            print(
                _value(dest),
                "=",
                f"({type_name(type)})",
                _value(src),
                end=";\n",
                file=out,
            )

        case _:
            raise NotImplementedError(
                f"cannot emit {builtins.type(op).__name__} operation"
            )


def _emit_terminator(out: TextIO, end: mir.Terminator, ret_style: CReturnStyle):
    match end:
        case mir.Jump(to):
            print(f"\tgoto block{to};", file=out)

        case mir.BranchZero(value, z_branch, nz_branch):
            print(
                f"\tif ({_value(value)}) goto block{nz_branch};",
                file=out,
            )
            print(f"\t\telse goto block{z_branch};", file=out)

        case mir.BranchEqual(lhs, rhs, eq_branch, ne_branch):
            print(
                f"\tif ({_value(lhs)} == {_value(rhs)}) goto block{eq_branch};",
                file=out,
            )
            print(f"\t\telse goto block{ne_branch};", file=out)

        case mir.BranchLess(lhs, rhs, lt_branch, ge_branch):
            print(
                f"\tif ({_value(lhs)} < {_value(rhs)}) goto block{lt_branch};",
                file=out,
            )
            print(f"\t\telse goto block{ge_branch};", file=out)

        case mir.Return(rets):
            match ret_style.convention:
                case CReturnConvention.Void:
                    print("\treturn;", file=out)
                case CReturnConvention.Single:
                    print(f"\treturn {_value(rets[0])};", file=out)
                case CReturnConvention.IsOK:
                    print("\treturn true;", file=out)
                case _:
                    raise NotImplementedError(
                        f"return convention {ret_style.convention.name} not implemented yet"
                    )

        case _:
            raise NotImplementedError(
                f"cannot emit {builtins.type(end).__name__} terminator"
            )


def return_style(func: mir.Function):
    match len(func.returns), func.fallible, func.error:
        case 0, False, _:
            return CReturnStyle(
                convention=CReturnConvention.Void,
                ctypename="void",
            )
        case 1, False, _:
            return CReturnStyle(
                convention=CReturnConvention.Single,
                ctypename=type_name(func.returns[0]),
            )
        case _, False, _:
            return CReturnStyle(
                convention=CReturnConvention.Struct,
                ctypename=f"krkReturns{func.id}",
            )
        case 0, True, None:
            return CReturnStyle(
                convention=CReturnConvention.IsOK,
                ctypename="bool",
            )
        case _, True, _:
            return CReturnStyle(
                convention=CReturnConvention.TaggedUnion,
                ctypename=f"krkReturns{func.id}",
            )


C_PRIMITIVES = {
    PrimitiveType.Integer: "int64_t",  # TEMP
    PrimitiveType.Int64: "int64_t",
    PrimitiveType.Int32: "int32_t",
    PrimitiveType.Int16: "int16_t",
    PrimitiveType.Int8: "int8_t",
    PrimitiveType.UInt64: "uint64_t",
    PrimitiveType.UInt32: "uint32_t",
    PrimitiveType.UInt16: "uint16_t",
    PrimitiveType.UInt8: "uint8_t",
    PrimitiveType.Decimal: "double",  # TEMP: VERY WRONG!
    PrimitiveType.Dec64: "double",  # TEMP: VERY WRONG!
    PrimitiveType.Dec32: "float",  # TEMP: VERY WRONG!
    PrimitiveType.Float64: "double",
    PrimitiveType.Float32: "float",
    PrimitiveType.Boolean: "bool",
    PrimitiveType.Byte: "uint8_t",
    PrimitiveType.Rune: "uint32_t",
}


def type_name(type: hir.Type) -> str:
    match type:
        case hir.SimpleType(PrimitiveType()):
            return C_PRIMITIVES[type.type]

        case _:
            raise NotImplementedError(f"unsupported type: {type}")


def _value(val: mir.Operand) -> str:
    match val:
        case mir.Temporary():
            return f"t{val.id}"
        case mir.LocalVar():
            return f"l{val.id}_{val.name}"
        case mir.Parameter():
            return f"p{val.index}_{val.name}"
        case mir.Constant(True):
            return "true"
        case mir.Constant(False):
            return "false"
        case mir.Constant(None):
            # TODO: how this gets expanded depends on the type
            return "((void*)0)"
        case mir.Constant():
            return str(val.value)  # FIXME: probably wrong
        case _:
            raise NotImplementedError(f"cannot handle {type(val).__name__} operands")
