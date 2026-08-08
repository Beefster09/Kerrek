
from dataclasses import dataclass

from frontend import ast, exprs
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
            exprs.fold_constants(node.expr)

        case ast.GlobalVariable():
            if node.expr and not isinstance(node.expr, ast.UnboundVar):
                exprs.fold_constants(node.expr)

        case ast.FuncDefinition():
            params_scope: Scope = {}
            for param in node.params:
                if param.default:
                    _, typ = exprs.fold_constants(param.default)
                    exprs.check_type(param.type, typ, param)
                    params_scope[param.name] = ParamVar(declaration=param)

            _validate_block(node.body, params_scope)


def _validate_block(block: ast.Block, *scopes: Scope):
    local_scope: Scope = {}
    for stmt in block.body:
        match stmt:
            case ast.Block():
                _validate_block(stmt, local_scope, *scopes)

            case ast.LocalConstant():
                val, typ = exprs.fold_constants(stmt.expr)
                print(stmt.name, typ, val)
                if stmt.type:
                    exprs.check_type(stmt.type, typ, stmt)

            case ast.LocalVariable():
                if isinstance(stmt.expr, ast.UnboundVar):
                    local_scope[stmt.name] = VarState(
                        declaration=stmt,
                        possibly_unbound=True,
                    )
                elif stmt.expr:
                    _, typ = exprs.fold_constants(stmt.expr)

                    if stmt.type is None:
                        typ = exprs.infer_type(typ, stmt)
                        stmt.realized_type = typ
                    else:
                        typ = exprs.check_type(stmt.type, typ, stmt)
                        assert not isinstance(typ, exprs.FlexType)
                        stmt.realized_type = typ

                    local_scope[stmt.name] = VarState(declaration=stmt)


