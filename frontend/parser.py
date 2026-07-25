import itertools
from typing import Iterable, Iterator

from frontend import ast
from frontend.lexer import Control, Punctuation, Token, Keyword, TokenData


class Parser:
    class TokenReader:
        def __init__(self, stream: Iterable[Token]):
            self._stream = iter(stream)
            self._buffer: list[Token] = []

        def peek(self, idx: int = 0) -> Token | None:
            self._fill(idx)
            if idx < len(self._buffer):
                return self._buffer[idx]
            else:
                return None

        def what(self, idx: int = 0):
            if tok := self.peek(idx):
                return tok.what
            else:
                return None

        def pop(self) -> Token:
            self._fill(1)
            if self._buffer and (tok := self._buffer.pop(0)):
                return tok
            else:
                raise StopIteration()

        def consume(self, count: int = 1):
            self._fill(count)
            self._buffer[:] = self._buffer[count:]

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
            return len(self._buffer) > 0

        def _fill(self, size: int):
            while len(self._buffer) < size:
                self._add_one()

        def _add_one(self):
            if tok := self._safe_next():
                self._buffer.append(tok)

        def _safe_next(self) -> Token | None:
            try:
                return next(self._stream)
            except StopIteration:
                return None

    class Error:
        pass

    def __init__(self, token_stream: Iterable[Token]):
        self.tokens = self.TokenReader(token_stream)
        first_tok = self.tokens.peek()
        self.src = first_tok.file if first_tok else None
        self.errors = []

    def parse(self) -> ast.File:

        if first_tok := self.tokens.peek():
            file = ast.File(source=first_tok.file)
        else:
            return ast.File(source=None)  # file is empty

        while stmt := self._toplevel_statement():
            match stmt:
                case ast._Import():
                    file.imports.append(stmt)
                case ast.Declaration():
                    file.declarations.append(stmt)

        return file

    def _toplevel_statement(self) -> ast.Node | None:
        while True:
            match self.tokens.what():
                case Keyword.Type:
                    raise NotImplementedError()

                case Keyword.Unit:
                    return self._unit_decl()

                case Control.EOL:
                    continue

                case _:
                    self.errors.append("TODO")
                    self.tokens.consume_until(Control.EOL)

    def _unit_decl(self) -> ast.UnitDecl | ast.UnitAlias | ast.UnitConversion:
        pass
