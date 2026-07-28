#!/usr/bin/env python3.13

from pathlib import Path
import sys

from frontend import lexer, parser

if __name__ == '__main__':
    file = Path(sys.argv[1])

    p = parser.Parser(lexer.tokenize(file))
    # for token in p.tokens._tokens:
    #     print(token)
    print(p.parse())
