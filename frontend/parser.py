from enum import Enum
import itertools
from types import EllipsisType
from typing import Iterable, Iterator, cast, overload

from frontend import ast
from frontend.lexer import Control, Identifier, Location, Numeric, Punctuation, String, Token, Keyword, TokenData, NumberLiteralForm


class Parser:
    class TokenReader:
        def __init__(self, stream: Iterable[Token]):
            self._tokens = list(stream)
            self._size = len(self._tokens)
            self.base = 0

        def peek(self, idx: int = 0) -> Token | None:
            if self.base + idx < self._size:
                return self._tokens[self.base + idx]
            else:
                return None

        def what(self, idx: int = 0):
            if tok := self.peek(idx):
                return tok.what
            else:
                return None

        def pop(self) -> Token:
            if self.base < self._size:
                tok = self._tokens[self.base]
                self.base += 1
                return tok
            else:
                raise StopIteration()

        def match(
            self,
            *tok_sequence: TokenData | type[TokenData] | EllipsisType,
            offset: int = 0,
        ) -> list[Token] | None:
            assert tok_sequence
            for i, expected in enumerate(tok_sequence, offset):
                if expected is ...:
                    continue

                if not self.match_one(expected, offset=i):
                    return None

            return self._tokens[self.base + offset:self.base + offset + len(tok_sequence)]

        def match_one[E: TokenData](
            self,
            expected: E | type[E],
            *,
            offset: int = 0,
        ) -> Token[E] | None:
            tok = self.peek(offset)

            if tok is None:
                return None

            if isinstance(expected, type):
                if not isinstance(tok.what, expected):
                    return None
            else:
                if tok.what is not expected:
                    return None

            return tok

        def match_and_consume(
            self,
            *tok_sequence: TokenData | type[TokenData] | EllipsisType,
            offset: int = 0,
        ) -> list[Token] | None:
            tokens = self.match(*tok_sequence, offset=offset)

            if tokens:
                self.consume(len(tokens))
                return tokens

            return None

        def match_one_and_consume[E: TokenData](
            self,
            expected: E | type[E],
            *,
            offset: int = 0,
        ) -> Token[E] | None:
            token = self.match_one(expected, offset=offset)

            if token:
                self.consume()
                return token

            return None

        def consume(self, count: int = 1) -> list[Token]:
            tokens = self._tokens[self.base:self.base + count]
            self.base = min(self.base + count, self._size)
            return tokens

        def consume_until(self, what: TokenData | type[TokenData]) -> list[Token]:
            if isinstance(what, type):
                def check(tok: TokenData) -> bool:
                    return isinstance(tok, what)
            else:
                def check(tok: TokenData) -> bool:
                    return tok is what

            for i in itertools.count():
                tok = self.what(i)
                if not tok:
                    return self.consume(i)

                if check(tok):
                    return self.consume(i)

            assert False, 'unreachable'

        def skip(
            self,
            *tok_sequence: TokenData | type[TokenData] | EllipsisType,
        ) -> None:
            assert tok_sequence
            for i, expected in enumerate(tok_sequence):
                if expected is ...:
                    continue

                if not self.match_one(expected, offset=i):
                    return

            self.base += len(tok_sequence)

        def skip_all(
            self,
            ignore: TokenData | type[TokenData],
        ) -> None:
            while True:
                if not self.match_one(ignore):
                    return

                self.base += 1

        def __bool__(self):
            return self.base < self._size

    class Error(Exception):
        def __init__(self, msg: str, start: Location | None = None, end: Location | None = None):
            self.msg = msg
            self.start = start
            self.end = end

    def __init__(self, token_stream: Iterable[Token]):
        self.tokens = self.TokenReader(token_stream)
        first_tok = self.tokens.peek()
        self.src = first_tok.file if first_tok else None
        self.errors: list[Parser.Error] = []

    def parse(self) -> ast.File:
        if first_tok := self.tokens.peek():
            file = ast.File(source=first_tok.file)
        else:
            return ast.File(source=None)  # file is empty

        try:
            while self.tokens:
                match stmt := self._toplevel_statement():
                    case ast._Import():
                        file.imports.append(stmt)

                    case ast.Declaration():
                        file.declarations.append(stmt)

        except StopIteration:
            self._emit_error("unexpected end of file")

        if self.errors:
            raise ExceptionGroup(f"encountered {len(self.errors)} errors while parsing", self.errors)

        return file

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

    def _toplevel_statement(self) -> ast.Node | None:
        tok = self.tokens.peek()
        if tok is None:
            return

        match tok.what:
            case Keyword.Type:
                raise NotImplementedError()

            case Keyword.Unit:
                return self._unit_decl()

            case Keyword.Func:
                return self._func_def()

            case Control.EOL:  # Empty line
                self.tokens.consume()
                return None

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
                self.tokens.consume_until(Control.EOL)
                return None

    def _unit_decl(self):
        if m := self.tokens.match_and_consume(
            Keyword.Unit,
            Keyword.Type,
            Identifier,
            Control.EOL,
        ):
            return ast.UnitTypeDecl(
                file=m[0].file,
                start=m[0].start,
                end=m[2].end,
                name=m[2].what,
            )

        elif m := self.tokens.match_and_consume(
            Keyword.Unit,
            Identifier,
            Punctuation.Colon,
        ):
            unit_type = self._qualname(required=True)  # plain unit declaration

            if unit_type and self._eol():
                return ast.UnitDecl(
                    file=m[0].file,
                    start=m[0].start,
                    end=unit_type.end,
                    name=m[1].what,
                    unit_type=unit_type,
                )

        elif m := self.tokens.match_and_consume(
            Keyword.Unit,
            Identifier,
            Keyword.Is,
            Punctuation.LT,
            Punctuation.GT,
            Control.EOL,
        ):
            # Special case for the empty compound unit a.k.a. "ratio"
            # it is the unit returned by trig functions
            name = m[1]
            return ast.UnitAlias(
                file=m[1].file,
                start=m[0].start,
                end=m[4].end,
                alias=m[1].what,
                base=ast.CompoundUnit(
                    file=m[3].file,
                    start=m[3].start,
                    end=m[4].end,
                    components=[],
                ),
            )

        elif m := self.tokens.match_and_consume(
            Keyword.Unit,
            Identifier,
            Keyword.Is,
        ):
            name = m[1]
            base = self._compound_unit(slash_ok=True, required=True)
            if base and self._eol():
                return ast.UnitAlias(
                    file=name.file,
                    start=m[0].start,
                    end=base.end,
                    alias=name.what,
                    base=base,
                )

        elif m := self.tokens.match_and_consume(
            Keyword.Unit,
            Identifier,
            Punctuation.Assign,
        ):
            # unit conversion
            self.tokens.consume_until(Control.EOL)
            # TODO
            return

        elif m := self.tokens.match_and_consume(
            Keyword.Unit,
            Identifier,
            Control.EOL,
        ):
            # untyped unit declaration
            return ast.UnitDecl(
                file=m[0].file,
                start=m[0].start,
                end=m[1].end,
                name=m[1].what,
            )

        self._emit_error(f"invalid form of unit declaration")
        self.tokens.consume_until(Control.EOL)

    def _compound_unit(self, *, slash_ok=False, required=False):
        components: list[ast.UnitComponent] = []
        seen_slash = False
        while qualname := self._qualname():
            exponent = 1
            comp_start = qualname.start
            comp_end = qualname.end

            if m := self.tokens.match_and_consume(Punctuation.Caret, Numeric):
                exp = m[1]

                assert isinstance(exp.what, Numeric)

                if exp.what.form is NumberLiteralForm.DecimalInteger:
                    exponent = cast(int, exp.what.value)
                    comp_end = exp.end
                else:
                    self._emit_error("a decimal integer literal is required here", exp)

            if slash_ok:
                if seen_slash:
                    exponent = -exponent
                elif self.tokens.match_one_and_consume(Punctuation.Slash):
                    seen_slash = True

            components.append(ast.UnitComponent(
                file=qualname.file,
                start=comp_start,
                end=comp_end,
                base=qualname,
                exponent=exponent,
            ))

        if not components:
            if required:
                self._emit_error("expected a unit here")
            return None

        return ast.CompoundUnit(
            file=components[0].file,
            start=components[0].start,
            end=components[-1].end,
            components=components,
        )

    def _func_def(self) -> ast.FuncDefinition | None:
        func_keyword = self.tokens.match_one_and_consume(Keyword.Func)
        assert func_keyword

        func_name = self.tokens.match_one_and_consume(Identifier)

        if not func_name:
            self._emit_error("expected function name")
            return

        params = self._param_list()
        if not params:
            self._emit_error("expected a parameter list")
            return

        if self.tokens.match_one_and_consume(Punctuation.Arrow):
            return_type = self._type_expr()  # TODO: multiple return types

            if return_type:
                return_types = [return_type]
            else:
                return_types = []

            if self.tokens.match_one_and_consume(Punctuation.Bang):
                error_type = self._type_expr() or ...
            else:
                error_type = None
        else:
            return_types = []
            error_type = None

        # TODO: requires

        body = self._block()

        if not self._eol():
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
        if not self.tokens.match_one_and_consume(Punctuation.LParen):
            return

        params: list[ast.FormalParameter] = []

        while m := self.tokens.match_and_consume(Identifier, Punctuation.Colon):
            self.tokens.skip(Punctuation.Dollar) # TODO: mark the type as polymorphic

            param_type = self._type_expr()
            if not param_type:
                return

            if self.tokens.match_one_and_consume(Punctuation.Assign):
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

            if self.tokens.match_and_consume(Punctuation.Comma):
                self.tokens.skip_all(Control.EOL)

            else:
                break

        if not self.tokens.match_one_and_consume(Punctuation.RParen):
            self._emit_error("expected end of parameter list")
            return

        return params

    def _block(self) -> ast.Block | None:
        begin = self.tokens.match_one_and_consume(Punctuation.LCurly)
        if not begin:
            return

        trailing_junk = self.tokens.consume_until(Punctuation.RCurly)
        if trailing_junk:
            self._emit_error("unable to parse content in block body", trailing_junk[0].start, trailing_junk[-1].end)

        end = self.tokens.match_one_and_consume(Punctuation.RCurly)
        if not end:
            self._emit_error("block not closed")
            return

    def _type_expr(self, *, required=True) -> ast.TypeExpression | None:
        if st := self._simple_type():
            return st

        if required:
            self._emit_error("expected a type expression here")

    def _simple_type(self) -> ast.TypeExpression | None:
        if qualname := self._qualname():
            base = ast.SimpleType(
                file=qualname.file,
                start=qualname.start,
                end=qualname.end,
                type_name=qualname,
            )
        else:
            print('haldo', self.tokens.peek())
            return None

        if lt := self.tokens.match_one_and_consume(Punctuation.LT):
            base.unit = self._compound_unit(slash_ok=True) or ast.CompoundUnit(
                file=lt.file,
                start=lt.end,
                end=lt.end,
                components=[],
            )

            gt = self.tokens.match_one_and_consume(Punctuation.GT)
            if gt:
                base.end = gt.end
            else:
                base.end = base.unit.end
                self._emit_error("unit on type not closed")

        return base

    def _expr(self) -> ast.Expression | None:
        pass

    def _qualname(self, required=False) -> ast.QualifiedName | None:
        root = self.tokens.match_one_and_consume(Identifier)

        if not root:
            if required:
                self._emit_error("expected a qualified name here")
            return None

        path = [root.what]
        start = root.start
        end = root.end

        while m := self.tokens.match_and_consume(Punctuation.Dot, Identifier):
            assert isinstance(m[1].what, Identifier)
            path.append(m[1].what)
            end = m[1].end

        return ast.QualifiedName(
            file=root.file,
            start=start,
            end=end,
            path=path,
        )

    def _eol(self) -> bool:
        eol = self.tokens.match_one_and_consume(Control.EOL)
        if eol:
            return True
        else:
            self._emit_error("end of line expected here")
            return False


