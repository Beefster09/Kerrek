from enum import Enum
import itertools
from typing import Iterable, Iterator

from frontend import ast
from frontend.lexer import Control, Identifier, Numeric, Punctuation, String, Token, Keyword, TokenData


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

        def consume(self, count: int = 1):
            self.base = min(self.base + count, self._size)

        def consume_until(self, what: TokenData | type[TokenData]):
            if isinstance(what, type):
                def check(tok: TokenData) -> bool:
                    return isinstance(tok, what)
            else:
                def check(tok: TokenData) -> bool:
                    return tok is what

            for i in itertools.count():
                tok = self.what(i)
                if not tok:
                    return

                if check(tok):
                    self.consume(i)
                    return

        def __bool__(self):
            return self.base < self._size

    class Error(Exception):
        pass

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
            self.errors.append(self.Error("unexpected EOF"))

        if self.errors:
            raise ExceptionGroup(f"encountered {len(self.errors)} errors while parsing", self.errors)

        return file

    def _toplevel_statement(self) -> ast.Node | None:
        tok = self.tokens.peek()
        if tok is None:
            return

        match tok.what:
            case Keyword.Type:
                raise NotImplementedError()

            case Keyword.Unit:
                return self._unit_decl()

            case Control.EOL:
                self.tokens.consume()
                return None

            case _:
                match tok.what:
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

                self.errors.append(self.Error(f"unexpected {tok_str} in '{tok.file}' at {tok.start}"))
                self.tokens.consume_until(Control.EOL)
                return None

    def _unit_decl(self) -> ast.UnitDecl | ast.UnitAlias | ast.UnitConversion | None:
        match self.tokens.what(1):
            case Keyword.Type:
                self.tokens.consume(2)
                name = self.tokens.pop()

            case _:
                self.tokens.consume_until(Control.EOL)
