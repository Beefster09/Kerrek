from collections.abc import Iterable
from decimal import Decimal
from enum import Enum, auto
from pathlib import Path
from types import EllipsisType
from typing import cast, overload

from frontend import ast, diagnostics
from frontend.common import Location
from frontend.lexer import (
    Identifier,
    Keyword,
    NumberLiteralForm,
    Numeric,
    Punctuation,
    Rune,
    String,
    Token,
    TokenData,
    tokenize,
)


class Associativity(Enum):
    NonAssociative = auto()
    Left = auto()
    Right = auto()


BINOPS = {
    Punctuation.DStar: (100, ast.BinaryOp.Power, Associativity.Right),
    Punctuation.Star: (80, ast.BinaryOp.Multiply, Associativity.Left),
    Punctuation.Slash: (80, ast.BinaryOp.TrueDivide, Associativity.Left),
    Punctuation.DSlash: (80, ast.BinaryOp.FloorDivide, Associativity.Left),
    Punctuation.Percent: (80, ast.BinaryOp.Remainder, Associativity.Left),
    Punctuation.Plus: (60, ast.BinaryOp.Add, Associativity.Left),
    Punctuation.Minus: (60, ast.BinaryOp.Subtract, Associativity.Left),
    Keyword.Mod: (50, ast.BinaryOp.Modulo, Associativity.Left),
    Keyword.Is: (40, ast.BinaryOp.Is, Associativity.NonAssociative),
    Keyword.IsNot: (40, ast.BinaryOp.IsNot, Associativity.NonAssociative),
    Punctuation.EQ: (40, ast.BinaryOp.Equal, Associativity.NonAssociative),
    Punctuation.NE: (40, ast.BinaryOp.NotEqual, Associativity.NonAssociative),
    Punctuation.GT: (40, ast.BinaryOp.Greater, Associativity.NonAssociative),
    Punctuation.GE: (40, ast.BinaryOp.GreaterEqual, Associativity.NonAssociative),
    Punctuation.LT: (40, ast.BinaryOp.Less, Associativity.NonAssociative),
    Punctuation.LE: (40, ast.BinaryOp.LessEqual, Associativity.NonAssociative),
    Keyword.And: (20, ast.BinaryOp.And, Associativity.Left),
    Keyword.Or: (10, ast.BinaryOp.Or, Associativity.Left),
}

UNOPS = {
    Punctuation.Plus: (90, ast.UnaryOp.Positive),
    Punctuation.Minus: (90, ast.UnaryOp.Negate),
    Keyword.Not: (30, ast.UnaryOp.Not),
}


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
            *tok_sequence: (
                TokenData
                | type[TokenData]
                | tuple[TokenData | type[TokenData], ...]
                | EllipsisType
            ),
            offset: int = 0,
        ) -> list[Token] | None:
            assert tok_sequence
            base = self._base + offset

            for i, expected in enumerate(tok_sequence, base):
                if i >= self._size:
                    return None

                actual = self._tokens[i]

                if expected is ...:
                    continue

                if not self._token_is(actual, expected):
                    return None

            return self._tokens[base : base + len(tok_sequence)]

        def _token_is[E: TokenData](
            self,
            token: Token,
            expected: E | type[E] | tuple[E | type[E], ...],
        ) -> bool:
            if isinstance(expected, tuple):
                if any(self._token_is(token, exp) for exp in expected):
                    return True
            elif isinstance(expected, type):
                if isinstance(token.what, expected):
                    return True
            else:
                if token.what is expected:
                    return True

            return False

        def match(
            self,
            *tok_sequence: (
                TokenData
                | type[TokenData]
                | tuple[TokenData | type[TokenData], ...]
                | EllipsisType
            ),
        ) -> list[Token] | None:
            """match and consume the next tokens if they match the sequence

            if same_line is True, the sequence will only match if all the tokens
            appeared on the same line as each other *and* the previous token

            if one_line is True, the sequence will only match if all the tokens
            appeared on the same line

            An ellipsis will match any one token
            """
            tokens = self._match_seq(*tok_sequence)

            if tokens:
                self.advance(len(tokens))
                return tokens

            return None

        def match_one[E: TokenData](
            self,
            expected: E | type[E],
        ) -> Token[E] | None:
            token = self._match_seq(expected)

            if token:
                self.advance()
                return token[0]

            return None

        def match_any(
            self,
            *expected: TokenData | type[TokenData],
        ) -> Token | None:
            token = self._match_seq(expected)

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

        def attempt_recovery(self):
            for i in range(self._base, self._size):
                if self._tokens[i].what in (Punctuation.Semicolon, Punctuation.RCurly):
                    self._base = min(i + 1, self._size)
                    return

            self._base = self._size

    def __init__(self, token_stream: Iterable[Token], max_errors=100):
        self.tokens = self.TokenReader(token_stream)
        first_tok = self.tokens.peek()
        self.src = first_tok.file if first_tok else None
        self.max_errors = max_errors

    @overload
    def _emit_error(self, message: str): ...

    @overload
    def _emit_error(self, message: str, token: Token, /): ...

    @overload
    def _emit_error(self, message: str, loc: Location, /): ...

    @overload
    def _emit_error(self, message: str, start: Location, end: Location, /): ...

    def _emit_error(
        self,
        message: str,
        token_or_start: Token | Location | None = None,
        end_maybe: Location | None = None,
    ):
        if isinstance(token_or_start, Location):
            if end_maybe:
                diagnostics.error(
                    message, self.src, token_or_start, end_maybe, category="syntax"
                )
            else:
                diagnostics.error(
                    message, self.src, token_or_start, token_or_start, category="syntax"
                )
        else:
            bad_tok = token_or_start or self.tokens.peek()
            if bad_tok:
                diagnostics.error(
                    message, self.src, bad_tok.start, bad_tok.end, category="syntax"
                )
            else:
                diagnostics.error(
                    message,
                    self.src,
                    self.tokens[-1].end if self.tokens._size else None,
                    category="syntax",
                )

    def parse(self) -> ast.File:
        if first_tok := self.tokens.peek():
            file = ast.File(source=first_tok.file)
        else:
            return ast.File(source=None)  # file is empty

        annotations: list[ast.Annotation] = []

        def apply_annotations(it: ast.TopLevelItem):
            nonlocal annotations
            if annotations:
                it.annotations += annotations
                annotations = []

        while self.tokens:
            match stmt := self._toplevel_decl():
                case ast.Annotation():
                    annotations.append(stmt)

                case ast.Import():
                    apply_annotations(stmt)
                    file.imports.append(stmt)

                case ast.TopLevelDeclaration():
                    apply_annotations(stmt)
                    file.declarations.append(stmt)

        diagnostics.report()

        return file

    def _toplevel_decl(self) -> ast.TopLevelItem | ast.Annotation | None:
        tok = self.tokens.peek()
        assert tok

        match tok.what:
            case Punctuation.At:
                return self._annotation()

            case Keyword.Type:
                raise NotImplementedError()

            # case Keyword.Let:
            #     raise NotImplementedError()

            # case Keyword.Const:
            #     raise NotImplementedError()

            case Keyword.Unit:
                return self._unit_decl()

            case Keyword.Func:
                return self._func_def()

            case _:
                match tok.what:
                    case Keyword():
                        tok_str = f"'{tok.what.value}'"
                    case Enum():
                        tok_str = tok.what.name.rstrip("_")
                    case Identifier():
                        tok_str = f"Identifier '{tok.what}'"
                    case Numeric():
                        tok_str = f"Number '{tok.what.raw}'"
                    case String():
                        tok_str = f"String {tok.what.raw}"
                    case _:
                        tok_str = type(tok.what).__name__

                self._emit_error(f"unexpected {tok_str} in '{tok.file}' at {tok.start}")
                self.tokens.attempt_recovery()
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
                if mul.what.form not in (
                    NumberLiteralForm.DecimalInteger,
                    NumberLiteralForm.Decimal,
                ):
                    self._emit_error(
                        "decimal number required as multiplier for unit conversion", mul
                    )

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
                    if mul.what.form not in (
                        NumberLiteralForm.DecimalInteger,
                        NumberLiteralForm.Decimal,
                    ):
                        self._emit_error(
                            "decimal number required as multiplier for unit conversion",
                            mul,
                        )

                    multiplier = Decimal(mul.what.value)
                    end = mul.end
                else:
                    multiplier = Decimal(1)

            if m2 := self.tokens.match(Punctuation.Slash, Numeric):
                div = m2[1]
                if div.what.form not in (
                    NumberLiteralForm.DecimalInteger,
                    NumberLiteralForm.Decimal,
                ):
                    self._emit_error(
                        "decimal number required as divisor for unit conversion", div
                    )

                divisor = Decimal(div.what.value)
                end = div.end
            else:
                divisor = Decimal(1)

            if multiplier == Decimal(0):
                self._emit_error("unit conversions cannot multiply by zero")
            if divisor == Decimal(0):
                self._emit_error("unit conversions cannot divide by zero")

            if self._end_of_statement():
                return ast.UnitConversionDef(
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

        self._emit_error("invalid form of unit declaration")
        self.tokens.attempt_recovery()

    def _compound_unit(self, *, required=False):
        leading_hash = self.tokens.match_one(Punctuation.Hash)

        if (
            (t := self.tokens.peek())
            and isinstance(t.what, Numeric)
            and t.what.raw == "1"
        ):
            self.tokens.advance()
            return ast.CompoundUnit(
                file=t.file,
                start=leading_hash.start if leading_hash else t.start,
                end=t.end,
                components=[],
                is_absolute=leading_hash is not None,
            )

        components: list[ast.UnitComponent] = []
        in_denominator = False
        while qualname := self._qualname():
            exponent = 1
            comp_start = qualname.start
            comp_end = qualname.end

            if m := self.tokens.match(Punctuation.Caret, Numeric):
                exp = m[1]

                assert isinstance(exp.what, Numeric)

                if exp.what.form is NumberLiteralForm.DecimalInteger:
                    exponent = cast(int, exp.what.value)
                    comp_end = exp.end
                else:
                    self._emit_error("a decimal integer literal is required here", exp)

            if in_denominator:
                exponent = -exponent

            components.append(
                ast.UnitComponent(
                    file=qualname.file,
                    start=comp_start,
                    end=comp_end,
                    base=qualname,
                    exponent=exponent,
                )
            )

            if self.tokens.match(Keyword.Per):
                in_denominator = True

        if not components:
            if required:
                self._emit_error("expected a unit here").suggest(
                    'did you mean the dimensionless "unit" spelled as: 1 ?'
                )
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
            returns: list[ast.FuncReturn] = []

            while True:
                if m := self.tokens.match(Identifier, Punctuation.Colon):
                    name = m[0].what
                    start = m[0].start
                else:
                    name = None
                    if t := self.tokens.peek():
                        start = t.start
                    else:
                        self._emit_error("expected a return type here")
                        return None

                return_type = self._type_expr()
                if return_type is None:
                    self._emit_error("expected a return type here")
                    return None

                if self.tokens.match_one(Punctuation.Bar):
                    unit = self._compound_unit()
                    if unit is None:
                        self._emit_error("expected a unit here")
                        return None
                    end = unit.end
                else:
                    unit = None
                    end = return_type.end

                returns.append(
                    ast.FuncReturn(
                        file=return_type.file,
                        start=start,
                        end=end,
                        name=name,
                        type=return_type,
                        unit=unit,
                    )
                )

                if not self.tokens.match_one(Punctuation.Comma):
                    break

            if self.tokens.match_one(Punctuation.Bang):
                error_type = self._type_expr()
                fallible = True
            else:
                error_type = None
                fallible = False
        else:
            returns = []
            error_type = None
            fallible = False

        # TODO: requires

        body = self._block()

        self._end_of_statement()  # consume a semicolon if it's there

        if not body:
            self._emit_error("function body required")
            return

        return ast.FuncDefinition(
            file=func_name.file,
            start=func_keyword.start,
            end=body.end,
            name=func_name.what,
            params=params,
            returns=returns,
            error_type=error_type,
            fallible=fallible,
            body=body,
            requires=None,
        )

    def _param_list(self) -> list[ast.FormalParameter] | None:
        if not self.tokens.match_one(Punctuation.LParen):
            return

        params: list[ast.FormalParameter] = []

        while m := self.tokens.match(Identifier, Punctuation.Colon):
            param_type = self._type_expr(allow_generics=True)
            if not param_type:
                return

            if self.tokens.match_one(Punctuation.Bar):
                unit = self._compound_unit()
            else:
                unit = None

            if self.tokens.match_one(Punctuation.Assign):
                default = self._expr()
            else:
                default = None

            params.append(
                ast.FormalParameter(
                    file=m[0].file,
                    start=m[0].start,
                    end=param_type.end,
                    name=m[0].what,
                    type=param_type,
                    unit=unit,
                    default=default,
                )
            )

            if not self.tokens.match_one(Punctuation.Comma):
                break

        if not self.tokens.match_one(Punctuation.RParen):
            self._emit_error("expected end of parameter list")
            return

        return params

    def _type_expr(self, *, allow_generics=False) -> ast.TypeExpression | None:
        typ = None

        match self.tokens.what():
            case Punctuation.Dollar:
                if template := self.tokens.match(Punctuation.Dollar, Identifier):
                    typ = ast.GenericType(
                        file=template[0].file,
                        start=template[0].start,
                        end=template[1].end,
                        name=template[1].what,
                        bound=None,
                    )

                if not allow_generics:
                    self._emit_error("generic types are not allowed here")

            case (
                Punctuation.Caret
                | Keyword.Owned
                | Keyword.Shared
                | Keyword.Weak
                | Keyword.UnsafePtr
            ):
                typ = self._pointer_type()

            case Punctuation.LSquare:
                typ = self._array_type()

            case Keyword.Map:
                typ = self._map_type()

            case Punctuation.Question:
                q = self.tokens.pop()
                assert q
                if inner := self._type_expr(allow_generics=allow_generics):
                    typ = ast.OptionalType(
                        file=q.file,
                        start=q.start,
                        end=inner.end,
                        base=inner,
                    )
                else:
                    self._emit_error(
                        "expected a type expression after the optional specifier"
                    )

            case Punctuation.LParen:
                lp = self.tokens.pop()
                assert lp
                typ = self._type_expr(allow_generics=allow_generics)

                if typ:
                    if rp := self.tokens.match_one(Punctuation.RParen):
                        typ.start = lp.start
                        typ.end = rp.end
                    else:
                        self._emit_error("parenthesized type expression was not closed")
                else:
                    self._emit_error(
                        "expected a type expression inside the parentheses"
                    )

            case _:
                if st := self._simple_type():
                    typ = st

        if typ is None:
            self._emit_error("expected a type here")
            return None

        tags = []
        while tilde := self.tokens.match_one(Punctuation.Tilde):
            tag = self._qualname()
            if tag:
                tags.append(tag)
            else:
                self._emit_error("expected a tag name here")
                return None

        if tags:
            typ = ast.TypeWithTags(
                file=typ.file,
                start=typ.start,
                end=tags[-1].end,
                base=typ,
                tags=tags,
            )

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

        if to := self._type_expr():
            return ast.PointerType(
                file=prefix.file,
                start=prefix.start,
                end=to.end,
                to=to,
                ownership=own,
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
            case Punctuation.Semicolon:
                self.tokens.advance()
                diagnostics.notice(
                    "empty statement", tok.file, tok.start, tok.start, category="syntax"
                )
                return None

            case Keyword.Return:
                self.tokens.advance()
                values = []
                first_ret = self._expr()
                if first_ret:
                    values.append(first_ret)
                    while self.tokens.match_one(Punctuation.Comma):
                        val = self._expr()
                        if val:
                            values.append(val)
                        else:
                            break

                stmt = ast.ReturnStatement(
                    file=tok.file,
                    start=tok.start,
                    end=values[-1].end if values else tok.end,
                    values=values,
                )

            case Keyword.Let | Keyword.Const:
                is_const = tok.what is Keyword.Const
                self.tokens.advance()
                name = self.tokens.match_one(Identifier)
                if name is None:
                    self._emit_error("expected variable name here")
                    self.tokens.attempt_recovery()
                    return None

                if self.tokens.match_one(Punctuation.Colon):
                    typ = self._type_expr()
                else:
                    typ = None

                if self.tokens.match_one(Punctuation.Bar):
                    if self.tokens.match_one(Keyword.Nil):
                        unit = ast.IndeterminateUnit.NoUnit
                    elif self.tokens.match_one(Keyword.Placeholder):
                        unit = ast.IndeterminateUnit.Flexible
                    else:
                        unit = self._compound_unit()

                        if unit is None:
                            self._emit_error("expected a unit here")
                            self.tokens.attempt_recovery()
                            return None

                else:
                    unit = ast.IndeterminateUnit.Inferred

                if self.tokens.match_one(Punctuation.Assign):
                    if ell := self.tokens.match_one(Punctuation.Ellipsis_):
                        value = ast.UnboundVar(
                            file=ell.file,
                            start=ell.start,
                            end=ell.end,
                        )
                    else:
                        value = self._expr()

                        if value is None:
                            self._emit_error("expected an expression here")
                            self.tokens.attempt_recovery()
                            return None

                else:
                    value = None

                if is_const:
                    if value is None or isinstance(value, ast.UnboundVar):
                        self._emit_error(
                            "const declarations must be given a value", tok
                        )
                        return None

                    stmt = ast.LocalConstant(
                        file=tok.file,
                        start=tok.start,
                        end=value.end if value else tok.end,
                        name=name.what,
                        type=typ,
                        unit=unit,
                        expr=value,
                    )
                else:
                    stmt = ast.LocalVariable(
                        file=tok.file,
                        start=tok.start,
                        end=value.end if value else tok.end,
                        name=name.what,
                        type=typ,
                        unit=unit,
                        expr=value,
                    )

            case _:
                if expr := self._expr():
                    lvalues = [expr]

                    while comma := self.tokens.match_one(Punctuation.Comma):
                        lvalue = self._expr()

                        if lvalue is None:
                            self._emit_error("expected an expression after the comma")
                            self.tokens.attempt_recovery()
                            return None

                        lvalues.append(lvalue)

                    if eq := self.tokens.match_one(Punctuation.Assign):
                        rvalues: list[ast.Expression] = []
                        while True:
                            rvalue = self._expr()

                            if rvalue is None:
                                self._emit_error("expected an expression here")
                                self.tokens.attempt_recovery()
                                return None

                            rvalues.append(rvalue)

                            if comma := self.tokens.match_one(Punctuation.Comma):
                                pass
                            else:
                                break

                        stmt = ast.AssignStatement(
                            file=tok.file,
                            start=expr.start,
                            end=rvalues[-1].end,
                            dests=lvalues,
                            exprs=rvalues,
                        )
                    elif len(lvalues) != 1:
                        self._emit_error("expected an assignment here")

                    else:
                        stmt = ast.ExprStatement.from_node(expr, expr=expr)

                else:
                    self._emit_error("invalid start of statement")
                    self.tokens.attempt_recovery()
                    return None

        assert stmt is not None, (
            "you should have set stmt by now or error-returned, you dolt"
        )

        if self._end_of_statement():
            return stmt
        else:
            self._emit_error("expected end of statement here")
            self.tokens.attempt_recovery()

    def _expr(self) -> ast.Expression | None:
        expr = self._expr_atom()

        if expr is None:
            return

        if binop := self._binop_expr(expr):
            expr = binop

        if self.tokens.match(Keyword.Reinterpret, Keyword.Unit, Keyword.As):
            if to_unit := self._compound_unit():
                return ast.UnitReinterpretExpr(
                    file=expr.file,
                    start=expr.start,
                    end=to_unit.end,
                    expr=expr,
                    new_unit=to_unit,
                )
            else:
                self._emit_error("expected a target unit for unit reinterpretation")

        elif self.tokens.match_one(Keyword.As):
            if to_type := self._type_expr():
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

        elif ident := self.tokens.match_one(Identifier):
            atom = ast.NameExpr(
                file=ident.file,
                start=ident.start,
                end=ident.end,
                name=ident.what,
            )

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
        tok = self.tokens.peek()
        if tok is None:
            return None

        match tok.what:
            case Numeric():
                self.tokens.advance()

                unit = self._compound_unit()

                return ast.ScalarLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=unit.end if unit else tok.end,
                    value=tok.what,
                    unit=unit,
                )

            case String():
                self.tokens.advance()
                return ast.SimpleLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                    value=tok.what.value,
                )

            case Rune():
                self.tokens.advance()
                return ast.SimpleLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                    value=ast.RuneValue(tok.what.codepoint),
                )

            case Keyword.True_:
                self.tokens.advance()
                return ast.SimpleLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                    value=True,
                )

            case Keyword.False_:
                self.tokens.advance()
                return ast.SimpleLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                    value=False,
                )

            case Keyword.Nil:
                self.tokens.advance()
                return ast.SimpleLiteralExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                    value=None,
                )

            case Keyword.Placeholder:
                self.tokens.advance()
                return ast.PlaceholderExpr(
                    file=tok.file,
                    start=tok.start,
                    end=tok.end,
                )

    def _binop_expr(
        self, lhs: ast.Expression, min_precedence=0
    ) -> ast.Expression | None:
        while op_tok1 := self.tokens.peek():
            try:
                prec1, op, _ = BINOPS[op_tok1.what]
            except (KeyError, TypeError):
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
                except (KeyError, TypeError):
                    break

                if assoc is Associativity.NonAssociative and prec2 == prec1:
                    self._emit_error(
                        f"operators {op_tok1.what.value} and {op_tok2.what.value} are not associative"
                    )
                    return None

                if not (
                    prec2 > prec1 or assoc is Associativity.Right and prec2 == prec1
                ):
                    break

                rhs = self._binop_expr(rhs, prec1 + int(prec2 > prec1))
                if rhs is None:
                    return None

            lhs = ast.BinopExpr(
                file=lhs.file,
                start=lhs.start,
                end=rhs.end,
                lhs=lhs,
                rhs=rhs,
                op=op,
            )

        return lhs

    def _annotation(self) -> ast.Annotation | None:
        at = self.tokens.match_one(Punctuation.At)
        if not at:
            return None

        base = self._qualname()
        if not base:
            self._emit_error("expected annotation name after the @")
            return None

        if self._end_of_line():
            return ast.Annotation(
                file=at.file,
                start=at.start,
                end=base.end,
                base=base,
                args=[],  # TODO
            )
        else:
            self._emit_error("expected end of line here")

    def _qualname(
        self,
        *,
        required=False,
    ) -> ast.QualifiedName | None:
        root = self.tokens.match_one(Identifier)

        if not root:
            if required:
                self._emit_error("expected a qualified name here")
            return None

        path = [root.what]
        start = root.start
        end = root.end

        while m := self.tokens.match(Punctuation.Dot, Identifier):
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
        if self.tokens.what() is Punctuation.Semicolon:
            self.tokens.advance()
            return True

        return False

    def _end_of_line(self) -> bool:
        tok = self.tokens.peek()
        return tok is None or tok.first_on_line


def load(path: Path):
    p = Parser(tokenize(path))
    return p.parse()
