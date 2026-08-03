from __future__ import annotations

import math
import operator
from collections import Counter
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from pathlib import Path
from typing import Any, Literal, NewType

from frontend import diagnostics
from frontend import ast
from frontend import parser
from frontend.lexer import Identifier


SymbolID = NewType('SymbolID', int)
def _symbol_gen():
    sym_id = 1
    while True:
        yield SymbolID(sym_id)
        sym_id += 1

_NEXT_SYM = _symbol_gen()
SYMBOLS_BY_ID: dict[SymbolID, _Symbol] = {}

type Num = int | float | Decimal | Fraction

class EvalState(Enum):
    Unresolved = auto()
    Uncomputable = auto()


@dataclass(kw_only=True)
class _Symbol:
    id: SymbolID = field(default_factory=_NEXT_SYM.__next__)

    def __post_init__(self):
        SYMBOLS_BY_ID[self.id] = self


@dataclass(kw_only=True)
class Type(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Function(_Symbol):
    name: Identifier
    definition: ast.FuncDefinition
    params: list[Variable] | None = None


@dataclass(kw_only=True)
class Constant(_Symbol):
    name: Identifier
    type: Type | None = None
    value: Any = EvalState.Unresolved
    definition: ast.GlobalConstant | ast.LocalConstant


@dataclass(kw_only=True)
class Variable(_Symbol):
    name: Identifier
    type: Type | None = None
    initial_value: Any = EvalState.Unresolved
    definition: ast.GlobalConstant | ast.LocalVariable | ast.FormalParameter


@dataclass(kw_only=True)
class UnitType(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Unit(_Symbol):
    name: Identifier
    unit_type: UnitType | None = None
    definition: ast.UnitDecl | ast.UnitAlias | ast.UnitConversionDef
    conversions: dict[SymbolID, Fraction] = field(default_factory=dict)


@dataclass(kw_only=True)
class Capability(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Module(_Symbol):
    file: ast.File
    name: Identifier
    imports: dict[Identifier, Module] = field(default_factory=dict)
    types: dict[Identifier, Type] = field(default_factory=dict)
    funcs: dict[Identifier, Function] = field(default_factory=dict)
    constants: dict[Identifier, Constant] = field(default_factory=dict)
    variables: dict[Identifier, Variable] = field(default_factory=dict)
    unit_types: dict[Identifier, UnitType] = field(default_factory=dict)
    units: dict[Identifier, Unit] = field(default_factory=dict)
    capabilities: dict[Identifier, Capability] = field(default_factory=dict)

    def __contains__(self, name: Identifier):
        return (
            name in self.imports
            or name in self.types
            or name in self.funcs
            or name in self.constants
            or name in self.variables
            or name in self.unit_types
            or name in self.units
            or name in self.capabilities
        )

    def lookup(self, name: Identifier):
        if thing := self.imports.get(name):
            return thing

        if thing := self.types.get(name):
            return thing

        if thing := self.funcs.get(name):
            return thing

        if thing := self.constants.get(name):
            return thing

        if thing := self.variables.get(name):
            return thing

        if thing := self.unit_types.get(name):
            return thing

        if thing := self.units.get(name):
            return thing

        if thing := self.capabilities.get(name):
            return thing

        return None

    def __iter__(self):
        yield from self.types.values()
        yield from self.funcs.values()
        yield from self.constants.values()
        yield from self.variables.values()
        yield from self.unit_types.values()
        yield from self.units.values()
        yield from self.capabilities.values()


@dataclass
class Builtin:
    name: Identifier


BUILTINS = {
    Identifier(name): Builtin(Identifier(name))
    for name in [
        # - TYPES -
        'Integer',
        'Int128',
        'Int64',
        'Int32',
        'Int16',
        'Int8',
        'UInt128',
        'UInt64',
        'UInt32',
        'UInt16',
        'UInt8',
        'Byte',

        'Number',
        'Dec128',
        'Dec64',
        'Dec32',

        # Float types are in intrinsics:float

        'Boolean',
        'String',
        'Rune',

        'Any',

        # - ANNOTATIONS -
        'private',
        'deprecated',
        'forward',
        'pure',
    ]
}

WRITE_ONLY = Builtin(Identifier('_'))


@dataclass
class TemplateVar:
    name: Identifier


type Named = _Symbol | Builtin | TemplateVar

class CanonicalUnit(Counter[SymbolID]):
    def __str__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit = SYMBOLS_BY_ID[comp_id]
            unit_name = unit.name if isinstance(unit, (Unit, UnitType)) else '???'

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return ' '.join(components)
        else:
            return '<ratio>'

    def __repr__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit = SYMBOLS_BY_ID[comp_id]
            unit_name = unit.name if isinstance(unit, (Unit, UnitType)) else '???'

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return f"unit({' '.join(components)})"
        else:
            return 'unit()'

    def __mul__(self, exponent: int):
        if not isinstance(exponent, int):
            return NotImplemented

        result = CanonicalUnit()

        for comp, exp in self.items():
            result[comp] += exp * exponent

        return result

    __rmul__ = __mul__

    def inplace_combine(self, other: CanonicalUnit, exponent: int):
        for comp, exp in other.items():
            self[comp] += exp * exponent

    @staticmethod
    def combine(
        a: CanonicalUnit | None, a_exp: int,
        b: CanonicalUnit | None, b_exp: int,
    ) -> CanonicalUnit | None:
        if a is None and b is None:
            return None

        result = CanonicalUnit()

        if a is not None:
            for comp, exp in a.items():
                result[comp] += exp * a_exp

        if b is not None:
            for comp, exp in b.items():
                result[comp] += exp * b_exp

        return result

@dataclass
class ScalarValue:
    value: Num
    unit: CanonicalUnit | None
    absolute: bool = False

    def __bool__(self) -> bool:
        return bool(self.value)


class Resolver:
    def __init__(self, project_root: Path = Path.cwd()):
        self.project_root = project_root
        self.modules: dict[Path, Module] = {}

    def require(self, path: Path) -> Module:
        """Resolves imported modules and parses them if missing
        """
        path = path.absolute()

        if path in self.modules:
            return self.modules[path]

        module = Module(
            file=parser.load(path),
            name=Identifier(path.stem),
        )
        self.modules[path] = module

        for imp in module.file.imports:
            if shadowed := module.imports.get(imp.namespace):
                diagnostics.error(
                    f"import of {'/'.join(imp.module_path)}"
                    + f" conflicts with existing import of {shadowed.file.source}",
                    imp)

            module.imports[imp.namespace] = self.require(
                imp.get_filepath(self.project_root, path))

        return module

    def resolve_names(self):
        """Resolves qualified names to point to their definitions
        """

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._add_symbol(module, decl)

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._resolve_names(module, decl)

        diagnostics.report()


    def _resolve_names(
        self,
        module: Module,
        node: ast.Node,
        *scopes: dict[Identifier, Named],
    ):
        """Resolves qualified names to point to their definitions
        """
        match node:
            case ast.QualifiedName():
                self._resolve_name(module, node, *scopes)

            case ast.FuncDefinition():
                for annotation in node.annotations:
                    self._resolve_names(module, annotation, *scopes)

                params: dict[Identifier, Named] = {}
                templates: dict[Identifier, Named] = {}

                for param in node.params:
                    if param.name == '_':
                        diagnostics.error("placeholder ('_') is not a valid parameter name", node)
                        return

                    if param.name in params:
                        diagnostics.error(f"duplicate parameter name '{param.name}'", param)

                    params[param.name] = Variable(name=param.name, definition=param)

                    for sub in param.type_.walk():
                        if isinstance(sub, ast.SimpleTemplateType):
                            templates[sub.name] = TemplateVar(sub.name)

                    self._resolve_names(module, param.type_, templates, *scopes)

                for ret in node.return_types:
                    self._resolve_names(module, ret, templates, *scopes)

                if node.error_type is not ... and node.error_type is not None:
                    self._resolve_names(module, node.error_type, templates, *scopes)

                if node.capabilities_required:
                    self._resolve_names(module, node.capabilities_required, *scopes)

                self._resolve_names(module, node.body, params, templates, *scopes)

            case ast.Block():
                local_scope = {}
                for stmt in node.body:
                    self._resolve_names(module, stmt, local_scope, *scopes)

            case ast.LocalVariable() | ast.LocalConstant():
                if node.name == '_':
                    diagnostics.error("placeholder ('_') is not a valid variable name", node)
                    return

                if node.type:
                    self._resolve_names(module, node.type, *scopes)
                if node.expr:
                    self._resolve_names(module, node.expr, *scopes)

                local_scope = scopes[0]
                if node.name in local_scope:
                    diagnostics.error(f"local with name '{node.name}' is already defined", node)
                    return
                elif any(node.name in scope for scope in scopes[1:]):
                    diagnostics.notice(f"local '{node.name}' shadows previously defined local", node)
                elif node.name in module:
                    diagnostics.notice(f"local '{node.name}' shadows module global", node)
                elif node.name in BUILTINS:
                    diagnostics.notice(f"local '{node.name}' shadows builtin", node)

                if isinstance(node, ast.LocalConstant):
                    local_scope[node.name] = node.resolves_to \
                        = Constant(name=node.name, definition=node)
                else:
                    local_scope[node.name] = Variable(name=node.name, definition=node)

            case _:
                for sub in node:
                    self._resolve_names(module, sub, *scopes)

    def _resolve_name(
        self,
        module: Module,
        qualname: ast.QualifiedName,
        *scopes: dict[Identifier, Named],
    ):
        base_name, *rest = qualname.path

        if base_name == '_':
            if rest:
                diagnostics.error("placeholder ('_') does not support field access", qualname)
                return

            qualname.resolves_to = WRITE_ONLY
            return

        elif '_' in qualname.path:
            diagnostics.error("placeholder ('_') is not a valid accessible field", qualname)
            return

        for scope in scopes:
            if base_name in scope:
                base = scope[base_name]
                break
        else:
            base = module.lookup(base_name) or BUILTINS.get(base_name)

        if not base:
            diagnostics.error(f"cannot resolve '{'.'.join(qualname.path)}'", qualname)
            return

        resolved = base

        if rest:
            raise NotImplementedError("qualified name traversal not yet supported")

        qualname.resolves_to = resolved

    def _add_symbol(self, module: Module, decl: ast.TopLevelDeclaration):
        def check_shadowing(node: ast.Node, kind: type, name: Identifier):
            if shadowed := module.lookup(name):
                diagnostics.warning(
                    f"{kind.__name__.lower()} '{name}' shadows {type(shadowed).__name__} '{shadowed.name}'",
                    node,
                )
            elif shadowed := BUILTINS.get(name):
                diagnostics.notice(f"{kind.__name__.lower()} '{name}' shadows a builtin", node)

        match decl:
            case ast.FuncDefinition():
                check_shadowing(decl, Function, decl.name)

                module.funcs[decl.name] = Function(name=decl.name, definition=decl)

            case ast.UnitTypeDecl() | ast.UnitTypeAliasDecl():
                check_shadowing(decl, UnitType, decl.name)

                module.unit_types[decl.name] = UnitType(name=decl.name, definition=decl)

            case ast.UnitDecl() | ast.UnitAlias():
                check_shadowing(decl, Unit, decl.name)

                module.units[decl.name] = Unit(name=decl.name, definition=decl)

            case ast.UnitConversionDef():
                if decl.dest in module.units:
                    return  # you can duplicate unit names for conversions

                check_shadowing(decl, Unit, decl.dest)

                module.units[decl.dest] = Unit(name=decl.dest, definition=decl)

                # the actual conversion has to be resolved later

    def canonicalize_units(self):
        for module in self.modules.values():
            for decl in module.file.declarations:
                for node in decl.walk():
                    if isinstance(node, ast.CompoundUnit):
                        self._ensure_canonical_unit(node)

        diagnostics.report()

    def _ensure_canonical_unit(self, unit: ast.CompoundUnit):
        if unit.canonical is not None:
            return

        unit.canonical = CanonicalUnit()

        for component in unit.components:
            resolved = component.base.resolves_to
            if isinstance(resolved, (Unit, UnitType)):
                if isinstance(resolved.definition, ast.UnitAlias):
                    self._ensure_canonical_unit(resolved.definition.base)
                    assert resolved.definition.base.canonical is not None
                    unit.canonical.inplace_combine(
                        resolved.definition.base.canonical, component.exponent,
                    )
                else:
                    unit.canonical[resolved.id] += component.exponent
            else:
                diagnostics.error(f"{component.base} is not a unit or unit type", component.base)

    def calculate_constants(self):
        """calculates compile-time known values:

        - global constants
        - local constants
        - default values of struct fields
        - default values of function parameters (usually)
        - initial values of global variables (sometimes)
        """
        for module in self.modules.values():
            for const in module.constants.values():
                _ensure_const_evaluated(const)

            for func in module.funcs.values():
                for stmt in func.definition.body.walk_statements():
                    if isinstance(stmt, ast.LocalConstant):
                        assert stmt.resolves_to, "this should have been defined by now"
                        _ensure_const_evaluated(stmt.resolves_to)

        diagnostics.report()


def _ensure_const_evaluated(const: Constant):
    if const.value is EvalState.Unresolved:
        try:
            const.value = evaluate(const.definition.expr)
        except Exception as err:
            diagnostics.error(f"value for {const.name} cannot be computed at compile time: {err}", const.definition)
            const.value = EvalState.Uncomputable

    return const.value


def evaluate(node: ast.Expression):
    match node:
        case ast.SimpleLiteralExpr():
            return node.value
        case ast.ScalarLiteralExpr():
            return ScalarValue(node.value.value, node.unit.canonical if node.unit else None)

        case ast.BinopExpr():
            return _eval_binop(node)

        case ast.QualnameExpr():
            resolved = node.name.resolves_to
            if isinstance(resolved, Constant):
                value = _ensure_const_evaluated(resolved)
                if value is EvalState.Uncomputable:
                    raise TypeError(f"const {'.'.join(node.name.path)} was unable to be evaluated")
                return value
            elif isinstance(resolved, Unit):
                if isinstance(resolved.definition, ast.UnitAlias):
                    return ScalarValue(1, resolved.definition.base.canonical)
                else:
                    return ScalarValue(1, CanonicalUnit([resolved.id]))
            else:
                raise TypeError(f"{'.'.join(node.name.path)} does not name a constant or unit")

        case _:
            raise TypeError(f"no compile-time evaluation is defined for {type(node).__name__}")


def remainder(lhs, rhs):
    if isinstance(lhs, int):
        return lhs % rhs
    else:
        return lhs - (math.floor(lhs / rhs) * rhs)


def modulo(lhs, rhs):
    rem = remainder(lhs, rhs)

    if rem >= 0:
        return rem
    else:
        return rhs + rem


BINOP_FUNCS = {
    ast.Operator.Add: operator.add,
    ast.Operator.Subtract: operator.sub,
    ast.Operator.Multiply: operator.mul,
    ast.Operator.Divide: operator.truediv,
    ast.Operator.FloorDivide: operator.floordiv,
    ast.Operator.Power: operator.pow,

    ast.Operator.Modulo: modulo,
    ast.Operator.Remainder: math.remainder,  # TEMP: incorrect - does not properly support decimal or fraction

    ast.Operator.Equal: operator.eq,
    ast.Operator.NotEqual: operator.ne,
    ast.Operator.Less: operator.lt,
    ast.Operator.LessEqual: operator.le,
    ast.Operator.Greater: operator.gt,
    ast.Operator.GreaterEqual: operator.ge,
}


def _eval_binop(binop: ast.BinopExpr):
    lhs = evaluate(binop.lhs)
    rhs = evaluate(binop.rhs)
    match binop.op, lhs, rhs:
        case (_, EvalState.Uncomputable, _) | (_, _, EvalState.Uncomputable):
            return EvalState.Uncomputable

        case (ast.Operator.Equal, None, _) | (ast.Operator.Equal, _, None):
            return lhs is None and rhs is None

        case (ast.Operator.NotEqual, None, _) | (ast.Operator.NotEqual, _, None):
            return not (lhs is None and rhs is None)

        case (_, None, _) | (_, _, None):
            return None

        case ast.Operator.Multiply, bool(), _:
            return rhs if lhs else _zero(rhs)

        case ast.Operator.Multiply, _, bool():
            return lhs if rhs else _zero(lhs)

        case ast.Operator.Add, str(), str():
            return lhs + rhs

        case ast.Operator.And, _, _:
            return _truthy(lhs) and _truthy(rhs)

        case ast.Operator.Or, _, _:
            return _truthy(lhs) or _truthy(rhs)

        case (
            (
                ast.Operator.Add | ast.Operator.Subtract
                | ast.Operator.Remainder | ast.Operator.Modulo
                | ast.Operator.Equal | ast.Operator.NotEqual
                | ast.Operator.Less | ast.Operator.Greater
                | ast.Operator.LessEqual | ast.Operator.GreaterEqual
            ),
            ScalarValue(), ScalarValue(),
        ):
            if lhs.unit == rhs.unit:
                opfunc = BINOP_FUNCS[binop.op]
                return ScalarValue(opfunc(*_coerce(lhs.value, rhs.value)), lhs.unit)
            else:
                raise ValueError(f"incompatible units: ({lhs.unit}) and ({rhs.unit})")

        case ast.Operator.Multiply, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.mul(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, 1),
            )

        case ast.Operator.Divide, ScalarValue(), ScalarValue():
            return ScalarValue(
                Fraction(lhs.value) / Fraction(rhs.value),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.Operator.FloorDivide, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.floordiv(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.Operator.Power, ScalarValue(), ScalarValue():
            if rhs.unit:
                raise ValueError("exponents must be unitless")

            if lhs.unit:
                frac_exp = Fraction(rhs.value)
                if frac_exp.is_integer():
                    new_unit = lhs.unit * frac_exp.numerator

                else:
                    raise ValueError("fractional exponents not yet supported for values with units")
            else:
                new_unit = None

            return ScalarValue(
                operator.pow(*_coerce(lhs.value, rhs.value)),
                new_unit,
            )

        case _:
            raise ValueError(
                f"no evaluation defined for operator {binop.op.value}"
                + f" on types {type(lhs).__name__} and {type(rhs).__name__}")


def _zero(value):
    match value:
        case ScalarValue():
            return ScalarValue(type(value.value)(), value.unit)
        case str():
            return ""
        case bool():
            return False
        case None:
            return None
        case _:
            raise TypeError(f"cannot determine zero value for {type(value)}")


def _truthy(value) -> bool:
    match value:
        case bool():
            return value
        case None:
            return False
        case _:
            raise TypeError("compile-time truthiness is only defined for bool and nil")


def _coerce(a: Num, b: Num) -> tuple[int, int] | tuple[float, float] | tuple[Decimal, Decimal] | tuple[Fraction, Fraction]:
    match a, b:
        case int(), int():
            return a, b
        case int(), float():
            return float(a), b
        case int(), Decimal():
            return Decimal(a), b
        case int(), Fraction():
            return Fraction(a), b

        case float(), int():
            return a, float(b)
        case float(), float():
            return a, b
        case float(), Decimal():
            return Decimal(a), b
        case float(), Fraction():
            return Fraction(a), b

        case Decimal(), int():
            return a, Decimal(b)
        case Decimal(), float():
            return a, Decimal(b)
        case Decimal(), Decimal():
            return a, b
        case Decimal(), Fraction():
            return Fraction(a), b

        case Fraction(), int():
            return a, Fraction(b)
        case Fraction(), float():
            return a, Fraction(b)
        case Fraction(), Decimal():
            return a, Fraction(b)
        case Fraction(), Fraction():
            return a, b
