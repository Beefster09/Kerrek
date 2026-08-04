
from dataclasses import dataclass

from frontend import ast, exprs
from frontend.lexer import Identifier


@dataclass(kw_only=True)
class VarState:
    type: exprs.ComptimeType
    possibly_unbound: bool = False  # needs to be a more complicated type but i'm just sketching it out


type Scope = dict[Identifier, VarState]


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
                    val, typ = exprs.fold_constants(param.default)
                    #_type_check(param.type, typ)
                    params_scope[param.name] = VarState(type=param.type)

            _validate_block(node.body, {})


def _validate_block(block: ast.Block, *scopes: Scope):
    local_scope: Scope = {}
    for stmt in block.body:
        match stmt:
            case ast.Block():
                _validate_block(stmt, local_scope, *scopes)

            case ast.LocalConstant():
                val, typ = exprs.fold_constants(stmt.expr)
                print(stmt.name, typ, val)
                #_type_check(param.type, typ)

            case ast.LocalVariable():
                if isinstance(stmt.expr, ast.UnboundVar):
                    local_scope[stmt.name] = VarState(type=..., possibly_unbound=True)
                elif stmt.expr:
                    exprs.fold_constants(stmt.expr)
                    local_scope[stmt.name] = VarState(type=...)


