from decimal import Decimal
import itertools
from enum import Enum, auto
from pathlib import Path
from types import EllipsisType
from typing import Iterable, cast, overload

from frontend import ast
from frontend.lexer import Identifier, Location, Numeric, Punctuation, String, Token, Keyword, TokenData, NumberLiteralForm, tokenize


class Associativity(Enum):
    NonAssociative = auto()
    Left = auto()
    Right = auto()

BINOPS = {
    Punctuation.DStar: (10, ast.Operator.Exponent, Associativity.Right),

    Punctuation.Star: (20, ast.Operator.Multiply, Associativity.Left),
    Punctuation.Slash: (20, ast.Operator.Divide, Associativity.Left),
    Punctuation.DSlash: (20, ast.Operator.FloorDivide, Associativity.Left),
    Punctuation.Percent: (20, ast.Operator.Modulo, Associativity.Left),

    Punctuation.Plus: (30, ast.Operator.Add, Associativity.Left),
    Punctuation.Minus: (30, ast.Operator.Subtract, Associativity.Left),

    Punctuation.EQ: (40, ast.Operator.Equal, Associativity.NonAssociative),
    Punctuation.NE: (40, ast.Operator.NotEqual, Associativity.NonAssociative),
    Punctuation.GT: (40, ast.Operator.Greater, Associativity.NonAssociative),
    Punctuation.GE: (40, ast.Operator.GreaterEqual, Associativity.NonAssociative),
    Punctuation.LT: (40, ast.Operator.Less, Associativity.NonAssociative),
    Punctuation.LE: (40, ast.Operator.LessEqual, Associativity.NonAssociative),

    Keyword.And: (50, ast.Operator.And, Associativity.Left),
    Keyword.Or: (50, ast.Operator.Or, Associativity.Left),
}

CONTINUATION_TOKENS = frozenset([
    *BINOPS,

    Punctuation.Dot,
    Keyword.As,
])


class Parser:
    class TokenReader:
        def __init__(self, stream: Iterable[Token]):
            self._tokens = list(stream)
            self._size = len(self._tokens)
            self._base = 0

        def __bool__(self):
            return self._base < self._size

        def __getitem__(self, idx: int) -> Token:
            real_idx = self._base + idx
            if 0 <= real_idx < self._size:
                return self._tokens[real_idx]

            raise IndexError(idx)

        def peek(self) -> Token | None:
            if self._base < self._size:
                return self._tokens[self._base]
            else:
                return None

        def pop(self) -> Token | None:
            if self._base < self._size:
                tok = self._tokens[self._base]
                self._base += 1
                return tok
            else:
                return None

        def what(self) -> TokenData | None:
            if self._base < self._size:
                return self._tokens[self._base].what
            else:
                return None

        def _match_seq(
            self,
            *tok_sequence: TokenData | type[TokenData] | EllipsisType,
            offset: int = 0,
            first_on_same_line: bool = False,
            rest_on_same_line: bool = False,
        ) -> list[Token] | None:
            assert tok_sequence
            base = self._base + offset

            for i, expected in enumerate(tok_sequence, base):
                if i >= self._size:
                    return None

                actual = self._tokens[i]

                if first_on_same_line and i == base and actual.first_on_line:
                    return None
                if rest_on_same_line and i > base and actual.first_on_line:
                    return None

                if expected is ...:
                    continue

                if not self._token_is(actual, expected):
                    return None

            return self._tokens[base:base+len(tok_sequence)]

        def _token_is[E: TokenData](
            self,
            token: Token,
            expected: E | type[E],
        ) -> Token[E] | None:
            if isinstance(expected, type):
                if not isinstance(token.what, expected):
                    return None
            else:
                if token.what is not expected:
                    return None

            return token

        def match(
            self,
            *tok_sequence: TokenData | type[TokenData] | EllipsisType,
            same_line: bool = False,
            one_line: bool = False,
        ) -> list[Token] | None:
            """match and consume the next tokens if they match the sequence

            if same_line is True, the sequence will only match if all the tokens
            appeared on the same line as each other *and* the previous token

            if one_line is True, the sequence will only match if all the tokens
            appeared on the same line

            An ellipsis will match any one token
            """
            tokens = self._match_seq(
                *tok_sequence,
                first_on_same_line=same_line,
                rest_on_same_line=same_line or one_line,
            )

            if tokens:
                self.advance(len(tokens))
                return tokens

            return None

        def match_one[E: TokenData](
            self,
            expected: E | type[E],
            *,
            same_line: bool = False,
        ) -> Token[E] | None:
            token = self._match_seq(expected, first_on_same_line=same_line)

            if token:
                self.advance()
                return token[0]

            return None

        def advance(self, count: int = 1) -> int:
            before = self._base
            self._base = min(self._base + count, self._size)
            return self._base - before

        def rewind(self, count: int = 1) -> int:
            before = self._base
            self._base = max(self._base - count, 0)
            return before - self._base

        def skip_line(self):
            for i in range(self._base, self._size):
                if self._tokens[i].first_on_line:
                    self._base = i
                    return

            self._base = self._size

    class Error(Exception):
        def __init__(self, msg: str, start: Location | None = None, end: Location | None = None):
            self.msg = msg
            self.start = start
            self.end = end

    def __init__(self, token_stream: Iterable[Token], max_errors=100):
        self.tokens = self.TokenReader(token_stream)
        first_tok = self.tokens.peek()
        self.src = first_tok.file if first_tok else None
        self.errors: list[Parser.Error] = []
        self.max_errors = max_errors

    @overload
    def _emit_error(self, message: str):
        ...

    @overload
    def _emit_error(self, message: str, token: Token, /):
        ...

    @overload
    def _emit_error(self, message: str, loc: Location, /):
        ...

    @overload
    def _emit_error(self, message: str, start: Location, end: Location, /):
        ...

    def _emit_error(
        self,
        message: str,
        token_or_start: Token | Location | None = None,
        end_maybe: Location | None = None,
    ):
        if isinstance(token_or_start, Location):
            if end_maybe:
                self.errors.append(self.Error(message, token_or_start, end_maybe))
            else:
                self.errors.append(self.Error(message, token_or_start, token_or_start))
        else:
            bad_tok = token_or_start or self.tokens.peek()
            if bad_tok:
                self.errors.append(self.Error(message, bad_tok.start, bad_tok.end))
            else:
                self.errors.append(self.Error(message))

        if len(self.errors) >= self.max_errors:
            self._report_errors()

    def _report_errors(self):
        if self.errors:
            raise ExceptionGroup(f"encountered {len(self.errors)} errors while parsing", self.errors)

    def parse(self) -> ast.File:
        if first_tok := self.tokens.peek():
            file = ast.File(source=first_tok.file)
        else:
            return ast.File(source=None)  # file is empty

        while self.tokens:
            match stmt := self._toplevel_decl():
                case ast.Import():
                    file.imports.append(stmt)

                case ast.Declaration():
                    file.declarations.append(stmt)

        self._report_errors()

        return file

    def _toplevel_decl(self) -> ast.Node | None:
        tok = self.tokens.peek()
        assert tok

        match tok.what:
            case Keyword.Type:
                raise NotImplementedError()

            case Keyword.Unit:
                return self._unit_decl()

            case Keyword.Func:
                return self._func_def()

            case _:
                match tok.what:
                    case Keyword():
                        tok_str = f"'{tok.what.value}'"
                    case Enum():
                        tok_str = tok.what.name.rstrip('_')
                    case Identifier():
                        tok_str = f"Identifier '{tok.what}'"
                    case Numeric():
                        tok_str = f"Number '{tok.what.raw}'"
                    case String():
                        tok_str = f"String {tok.what.raw}"
                    case _:
                        tok_str = type(tok.what).__name__

                self._emit_error(f"unexpected {tok_str} in '{tok.file}' at {tok.start}")
                self.tokens.advance()
                self.tokens.skip_line()
                return None

    def _unit_decl(self):
        if m := self.tokens.match(
            Keyword.Unit,
            Keyword.Type,
            Identifier,
            Keyword.Is,
        ):
            base = self._compound_unit(required=True)
            if not base:
                return None

            if self._end_of_statement():
                return ast.UnitTypeAliasDecl(
                    file=m[0].file,
                    start=m[0].start,
                    end=base.end,
                    name=m[2].what,
                    base=base,
                )
        elif m := self.tokens.match(
            Keyword.Unit,
            Keyword.Type,
            Identifier,
        ):
            if self._end_of_statement():
                return ast.UnitTypeDecl(
                    file=m[0].file,
                    start=m[0].start,
                    end=m[2].end,
                    name=m[2].what,
                )

        elif m := self.tokens.match(
            Keyword.Unit,
            Identifier,
            Punctuation.Colon,
        ):
            unit_type = self._qualname(required=True)  # plain unit declaration

            if unit_type and self._end_of_statement():
                return ast.UnitDecl(
                    file=m[0].file,
                    start=m[0].start,
                    end=unit_type.end,
                    name=m[1].what,
                    unit_type=unit_type,
                )

        elif m := self.tokens.match(
            Keyword.Unit,
            Identifier,
            Keyword.Is,
            Punctuation.LT,
            Punctuation.GT,
        ):
            # Special case for the empty compound unit a.k.a. "ratio"
            # it is the unit returned by trig functions
            name = m[1]
            if self._end_of_statement():
                return ast.UnitAlias(
                    file=m[1].file,
                    start=m[0].start,
                    end=m[4].end,
                    name=m[1].what,
                    base=ast.CompoundUnit(
                        file=m[3].file,
                        start=m[3].start,
                        end=m[4].end,
                        components=[],
                        is_absolute=False,
                    ),
                )

        elif m := self.tokens.match(
            Keyword.Unit,
            Identifier,
            Keyword.Is,
        ):
            name = m[1]
            base = self._compound_unit(required=True)
            if base and self._end_of_statement():
                return ast.UnitAlias(
                    file=name.file,
                    start=m[0].start,
                    end=base.end,
                    name=name.what,
                    base=base,
                )

        elif m := self.tokens.match(
            Keyword.Unit,
            Identifier,
            Punctuation.Assign,
        ):
            if m2 := self.tokens.match(Numeric, Punctuation.Star):
                mul = m2[0]
                if mul.what.form not in (NumberLiteralForm.DecimalInteger, NumberLiteralForm.Decimal):
                    self._emit_error("decimal number required as multiplier for unit conversion", mul)

                multiplier = Decimal(mul.what.value)

                src_unit = self._qualname(required=True)
                if src_unit is None:
                    return

                end = src_unit.end

            else:
                src_unit = self._qualname(required=True)
                if src_unit is None:
                    return

                end = src_unit.end

                if m2 := self.tokens.match(Punctuation.Star, Numeric):
                    mul = m2[1]
                    if mul.what.form not in (NumberLiteralForm.DecimalInteger, NumberLiteralForm.Decimal):
                        self._emit_error("decimal number required as multiplier for unit conversion", mul)

                    multiplier = Decimal(mul.what.value)
                    end = mul.end
                else:
                    multiplier = Decimal(1)

            if m2 := self.tokens.match(Punctuation.Slash, Numeric):
                div = m2[1]
                if div.what.form not in (NumberLiteralForm.DecimalInteger, NumberLiteralForm.Decimal):
                    self._emit_error("decimal number required as divisor for unit conversion", div)

                divisor = Decimal(div.what.value)
                end = div.end
            else:
                divisor = Decimal(1)

            if multiplier == Decimal(0):
                self._emit_error("unit conversions cannot multiply by zero")
            if divisor == Decimal(0):
                self._emit_error("unit conversions cannot divide by zero")

            if self._end_of_statement():
                return ast.UnitConversion(
                    file=m[0].file,
                    start=m[0].start,
                    end=end,
                    dest=m[1].what,
                    src=src_unit,
                    mult=multiplier,
                    div=divisor,
                )

        elif m := self.tokens.match(
            Keyword.Unit,
            Identifier,
        ):
            # untyped unit declaration
            if self._end_of_statement():
                return ast.UnitDecl(
                    file=m[0].file,
                    start=m[0].start,
                    end=m[1].end,
                    name=m[1].what,
                )

        self._emit_error(f"invalid form of unit declaration")
        self.tokens.advance()
        self.tokens.skip_line()

    def _compound_unit(self, *, required=False, same_line=False):
        leading_hash = self.tokens.match_one(Punctuation.Hash)

        components: list[ast.UnitComponent] = []
        in_denominator = False
        while qualname := self._qualname(same_line=same_line):
            exponent = 1
            comp_start = qualname.start
            comp_end = qualname.end

            if m := self.tokens.match(Punctuation.Caret, Numeric, same_line=True):
                exp = m[1]

                assert isinstance(exp.what, Numeric)

                if exp.what.form is NumberLiteralForm.DecimalInteger:
                    exponent = cast(int, exp.what.value)
                    comp_end = exp.end
                else:
                    self._emit_error("a decimal integer literal is required here", exp)

            if in_denominator:
                exponent = -exponent

            components.append(ast.UnitComponent(
                file=qualname.file,
                start=comp_start,
                end=comp_end,
                base=qualname,
                exponent=exponent,
            ))

            if self.tokens.match(Keyword.Per):
                in_denominator = True

        if not components:
            if required:
                self._emit_error("expected a unit here")
            return None

        return ast.CompoundUnit(
            file=components[0].file,
            start=leading_hash.start if leading_hash else components[0].start,
            end=components[-1].end,
            components=components,
            is_absolute=leading_hash is not None,
        )

    def _func_def(self) -> ast.FuncDefinition | None:
        func_keyword = self.tokens.match_one(Keyword.Func)
        assert func_keyword

        func_name = self.tokens.match_one(Identifier)

        if not func_name:
            self._emit_error("expected function name")
            return

        params = self._param_list()
        if params is None:
            self._emit_error("expected a parameter list")
            return

        if self.tokens.match_one(Punctuation.Arrow):
            return_type = self._type_expr()  # TODO: multiple return types ?

            if return_type:
                return_types = [return_type]
            else:
                return_types = []

            if self.tokens.match_one(Punctuation.Bang):
                error_type = self._type_expr() or ...
            else:
                error_type = None
        else:
            return_types = []
            error_type = None

        # TODO: requires

        body = self._block()

        if not self._end_of_statement():
            self._emit_error("expected end of line after function body")

        if not body:
            self._emit_error("function body required")
            return

        return ast.FuncDefinition(
            file=func_name.file,
            start=func_keyword.start,
            end=body.end,
            name=func_name.what,
            params=params,
            return_types=return_types,
            error_type=error_type,
            body=body,
        )

    def _param_list(self) -> list[ast.FormalParameter] | None:
        if not self.tokens.match_one(Punctuation.LParen):
            return

        params: list[ast.FormalParameter] = []

        while m := self.tokens.match(Identifier, Punctuation.Colon):
            param_type = self._type_expr(allow_templates=True)
            if not param_type:
                return

            if self.tokens.match_one(Punctuation.Assign):
                default = self._expr()
            else:
                default = None

            params.append(ast.FormalParameter(
                file=m[0].file,
                start=m[0].start,
                end=param_type.end,
                name=m[0].what,
                type_=param_type,
                default=default,
            ))

            if not self.tokens.match_one(Punctuation.Comma):
                break

        if not self.tokens.match_one(Punctuation.RParen):
            self._emit_error("expected end of parameter list")
            return

        return params

    def _type_expr(self, *, allow_no_base=False, allow_templates=False) -> ast.TypeExpression | None:
        typ = None

        match self.tokens.what():
            case Punctuation.Dollar:
                if template := self.tokens.match(Punctuation.Dollar, Identifier):
                    typ = ast.SimpleTemplateType(
                        file=template[0].file,
                        start=template[0].start,
                        end=template[1].end,
                        name=template[1].what,
                    )

                if not allow_templates:
                    self._emit_error("type templates are not allowed here")

            case Punctuation.Caret | Keyword.Owned | Keyword.Shared | Keyword.Weak | Keyword.UnsafePtr:
                typ = self._pointer_type()

            case Punctuation.LSquare:
                typ = self._array_type()

            case Keyword.Map:
                typ = self._map_type()

            case Punctuation.Question:
                q = self.tokens.pop()
                assert q
                if inner := self._type_expr(allow_templates=allow_templates):
                    typ = ast.OptionalType(
                        file=q.file,
                        start=q.start,
                        end=inner.end,
                        base=inner,
                    )
                else:
                    self._emit_error("expected a type expression after the optional specifier")

            case Punctuation.LParen:
                lp = self.tokens.pop()
                assert lp
                typ = self._type_expr(allow_templates=allow_templates)

                if typ:
                    if rp := self.tokens.match_one(Punctuation.RParen):
                        typ.start = lp.start
                        typ.end = rp.end
                    else:
                        self._emit_error("parenthesized type expression was not closed")
                else:
                    self._emit_error("expected a type expression inside the parentheses")

            case _:
                if st := self._simple_type():
                    typ = st

        if typ is None and not allow_no_base:
            return None

        while True:
            if lt := self.tokens.match_one(Punctuation.LT):
                if self.tokens.match_one(Keyword.Nil):
                    unit = None
                else:
                    unit = self._compound_unit() or ast.CompoundUnit(
                        file=lt.file,
                        start=lt.end,
                        end=lt.end,
                        components=[],
                        is_absolute=False,
                    )

                if gt := self.tokens.match_one(Punctuation.GT):
                    typ = ast.TypeWithUnit(
                        file=gt.file,
                        start=typ.start if typ else lt.start,
                        end=gt.end,
                        base=typ,
                        unit=unit,
                    )
                    continue
                else:
                    self._emit_error("unit on type not closed")

            elif at := self.tokens.match_one(Punctuation.Tilde):
                tag = self._qualname(same_line=True)
                if tag:
                    typ = ast.TypeWithTag(
                        file=tag.file,
                        start=typ.start if typ else at.start,
                        end=tag.end,
                        base=typ,
                        tag=tag,
                    )
                else:
                    self._emit_error("expected a tag name here")

            else:
                break

        return typ

    def _simple_type(self) -> ast.TypeExpression | None:
        if qualname := self._qualname():
            base = ast.SimpleType(
                file=qualname.file,
                start=qualname.start,
                end=qualname.end,
                type_name=qualname,
            )
        else:
            return None

        return base

    def _pointer_type(self):
        own: ast.PointerOwnership

        match self.tokens.what():
            case Punctuation.Caret:
                own = ast.PointerOwnership.Borrowed
            case Keyword.Owned:
                own = ast.PointerOwnership.Owned
            case Keyword.Shared:
                own = ast.PointerOwnership.Shared
            case Keyword.Weak:
                own = ast.PointerOwnership.Weak
            case Keyword.UnsafePtr:
                own = ast.PointerOwnership.Unsafe
            case _:
                self._emit_error("invalid prefix of pointer type")
                return None

        prefix = self.tokens.pop()
        assert prefix

        nullable = self.tokens.match(Punctuation.Question) is not None
        if to := self._type_expr():
            return ast.PointerType(
                file=prefix.file,
                start=prefix.start,
                end=to.end,
                to=to,
                ownership=own,
                nullable=nullable,
            )
        else:
            self._emit_error("pointer type must point to something")

    def _array_type(self):
        raise NotImplementedError()

    def _map_type(self):
        raise NotImplementedError()

    def _block(self) -> ast.Block | None:
        begin = self.tokens.match_one(Punctuation.LCurly)
        if not begin:
            return

        body: list[ast.Statement] = []

        while self.tokens:
            if end := self.tokens.match_one(Punctuation.RCurly):
                break
            elif stmt := self._statement():
                body.append(stmt)
        else:
            self._emit_error("block not closed")
            return

        return ast.Block(
            file=begin.file,
            start=begin.start,
            end=end.end,
            body=body,
        )

    def _statement(self) -> ast.Statement | None:
        stmt = None
        tok = self.tokens.peek()
        if tok is None:
            return

        match tok.what:
            case Keyword.Return:
                self.tokens.advance()
                retval = self._expr()

                stmt = ast.ReturnStatement(
                    file=tok.file,
                    start=tok.start,
                    end=retval.end if retval else tok.end,
                    value=retval,
                )

            case Keyword.Let | Keyword.Const:
                is_const = tok.what is Keyword.Const
                self.tokens.advance()
                name = self.tokens.match_one(Identifier)
                if name is None:
                    self._emit_error("expected variable name here")
                    self.tokens.skip_line()
                    return None

                if self.tokens.match_one(Punctuation.Colon):
                    typ = self._type_expr(allow_no_base=True)
                else:
                    typ = None

                if self.tokens.match_one(Punctuation.Assign):
                    if ell := self.tokens.match_one(Punctuation.Ellipsis_):
                        if is_const:
                            self._emit_error("const expressions cannot be explicitly undefined", ell)
                            self.tokens.skip_line()
                            return None

                        value = ast.UndefinedValue(
                            file=ell.file,
                            start=ell.start,
                            end=ell.end,
                        )
                    else:
                        value = self._expr()

                        if value is None:
                            self._emit_error("expected an expression here")

                else:
                    if is_const:
                        self._emit_error("const declarations must be given a value", tok)
                        self.tokens.skip_line()
                        return None

                    value = None

                stmt = ast.LocalDeclaration(
                    file=tok.file,
                    start=tok.start,
                    end=value.end if value else tok.end,
                    name=name.what,
                    type_=typ,
                    expr=value,
                    is_const=is_const,
                )

            case _:
                if expr := self._expr():
                    stmt = ast.ExprStatement.from_node(expr, expr=expr)
                else:
                    self._emit_error("invalid start of statement")
                    self.tokens.advance()
                    self.tokens.skip_line()
                    return None

        assert stmt is not None, "you should have set stmt by now or error-returned, you dolt"

        if self._end_of_statement():
            return stmt
        else:
            self._emit_error("expected end of statement here")
            self.tokens.skip_line()

    def _expr(self) -> ast.Expression | None:
        expr = self._expr_atom()

        if expr is None:
            return

        if binop := self._binop_expr(expr):
            expr = binop

        if self.tokens.match_one(Keyword.As):
            if to_type := self._type_expr(allow_no_base=True):
                return ast.CastExpr(
                    file=expr.file,
                    start=expr.start,
                    end=to_type.end,
                    expr=expr,
                    to=to_type,
                )
            else:
                self._emit_error("expected a target type for cast expression")

        return expr

    def _expr_atom(self) -> ast.Expression | None:
        atom = None

        if lp := self.tokens.match_one(Punctuation.LParen):
            inner = self._expr()
            if inner is None:
                self._emit_error("expected an expression inside the parentheses")
                return

            rp = self.tokens.match_one(Punctuation.RParen)
            if rp is None:
                self._emit_error("parenthesized expression was not closed", lp)
                return None

            inner.start = lp.start
            inner.end = rp.end

            atom = inner

        elif qualname := self._qualname():
            atom = ast.QualnameExpr.from_node(qualname, name=qualname)

        elif literal := self._literal_expr():
            return literal

        if atom is None:
            return

        while tok := self.tokens.peek():
            match tok.what:
                case Punctuation.Dot:  # field access
                    raise NotImplementedError()

                case Punctuation.Caret:  # dereference
                    raise NotImplementedError()

                case Punctuation.LParen:  # call
                    if tok.first_on_line:
                        break
                    raise NotImplementedError()

                case Punctuation.LSquare:  # index operator
                    if tok.first_on_line:
                        break
                    raise NotImplementedError()

                case _:
                    break

        return atom

    def _literal_expr(self):
        match tok := self.tokens.peek():
            case Token(what=Numeric()):
                self.tokens.advance()

                unit = self._compound_unit(same_line=True)

                return ast.ScalarExpr(
                    file=tok.file,
                    start=tok.start,
                    end=unit.end if unit else tok.end,
                    value=tok.what,
                    unit=unit,
                )

            case Token(what=String()):
                pass

    def _binop_expr(self, lhs: ast.Expression, min_precedence=0) -> ast.Expression | None:
        while op_tok1 := self.tokens.peek():
            try:
                prec1, op, _ = BINOPS[op_tok1.what]
            except KeyError:
                return lhs

            if prec1 < min_precedence:
                return lhs

            self.tokens.advance()
            rhs = self._expr_atom()
            if rhs is None:
                self._emit_error("expected a sub-expression here")
                return None

            while op_tok2 := self.tokens.peek():
                try:
                    prec2, _, assoc = BINOPS[op_tok2.what]
                except KeyError:
                    break

                if assoc is Associativity.NonAssociative and prec2 == prec1:
                    self._emit_error(f"operators {op_tok1.what.value} and {op_tok2.what.value} are not associative")
                    return None

                if not (
                    prec2 > prec1
                    or assoc is Associativity.Right and prec2 == prec1
                ):
                    break

                rhs = self._binop_expr(rhs, prec1 + int(prec2 > prec1))
                assert rhs

            lhs = ast.BinopExpr(
                file=lhs.file,
                start=lhs.start,
                end=rhs.end,
                lhs=lhs,
                rhs=rhs,
                op=op,
            )

        return lhs

    def _qualname(
        self,
        *,
        required=False,
        same_line=False,
        one_line=False,
    ) -> ast.QualifiedName | None:
        root = self.tokens.match_one(Identifier, same_line=same_line)

        if not root:
            if required:
                self._emit_error("expected a qualified name here")
            return None

        path = [root.what]
        start = root.start
        end = root.end

        while m := self.tokens.match(Punctuation.Dot, Identifier, same_line=one_line):
            assert isinstance(m[1].what, Identifier)
            path.append(m[1].what)
            end = m[1].end

        return ast.QualifiedName(
            file=root.file,
            start=start,
            end=end,
            path=path,
        )

    def _end_of_statement(self) -> bool:
        tok = self.tokens.peek()
        if tok is None:  # EOF
            return True

        match tok.what:
            case Punctuation.Semicolon:
                self.tokens.advance()
                return True

            case Punctuation.RCurly:
                return True

            case _:
                return tok.first_on_line and tok.what not in CONTINUATION_TOKENS


def load(path: Path):
    p = Parser(tokenize(path))
    return p.parse()
