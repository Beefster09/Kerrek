from dataclasses import dataclass

from frontend import ast, diagnostics, exprs
from frontend.lexer import Identifier


@dataclass(kw_only=True)
class VarState:
    declaration: ast.LocalVariable
    possibly_unbound: bool = False  # likely needs to be a more complicated type but i'm just sketching it out


@dataclass(kw_only=True)
class ParamVar:
    declaration: ast.FormalParameter


type Scope = dict[Identifier, VarState | ParamVar]


def validate(node: ast.TopLevelDeclaration):
    """does all of the core validation of the code:
    - constant folding
    - dependency cycle detection
    - type checking & inference
    - unit analysis
    - value label provenance checking
    - capability tracking
    """
    match node:
        case ast.GlobalConstant():
            exprs.evaluate(node.expr)

        case ast.GlobalVariable():
            if node.expr and not isinstance(node.expr, ast.UnboundVar):
                exprs.evaluate(node.expr)

        case ast.FuncDefinition():
            params_scope: Scope = {}
            for param in node.params:
                if param.default:
                    result = exprs.evaluate(param.default)
                    exprs.check_type(param.type, result.type, param)
                    params_scope[param.name] = ParamVar(declaration=param)

            _validate_block(node, node.body, params_scope)


def _validate_block(func: ast.FuncDefinition, block: ast.Block, *scopes: Scope):
    local_scope: Scope = {}
    for stmt in block.body:
        match stmt:
            case ast.Block():
                _validate_block(func, stmt, local_scope, *scopes)

            case ast.LocalConstant():
                result = exprs.evaluate(stmt.expr)
                if stmt.type:
                    exprs.check_type(stmt.type, result.type, stmt)

            case ast.LocalVariable():
                if isinstance(stmt.expr, ast.UnboundVar):
                    local_scope[stmt.name] = VarState(
                        declaration=stmt,
                        possibly_unbound=True,
                    )
                elif stmt.expr:
                    result = exprs.evaluate(stmt.expr)

                    if stmt.type is None:
                        typ = exprs.infer_type(result.type, stmt)
                        stmt.realized_type = typ
                    else:
                        typ = exprs.check_type(stmt.type, result.type, stmt)
                        assert not isinstance(typ, exprs.FlexType)
                        stmt.realized_type = typ

                    local_scope[stmt.name] = VarState(declaration=stmt)

            case ast.ReturnStatement():
                if len(stmt.values) < len(func.returns):
                    diagnostics.error(
                        "return statement has too few values"
                        + f" (expected {len(func.returns)}, got {len(stmt.values)})",
                        stmt,
                    )
                    continue

                if len(stmt.values) > len(func.returns):
                    diagnostics.error(
                        "return statement has too many values"
                        + f" (expected {len(func.returns)}, got {len(stmt.values)})",
                        stmt,
                    )
                    continue

                for ret, value in zip(func.returns, stmt.values, strict=True):
                    result = exprs.evaluate(value)
                    typ = exprs.check_type(ret.type, result.type, value)
                    assert not isinstance(typ, exprs.FlexType)
                    value.required_type = typ
