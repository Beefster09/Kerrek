#!/usr/bin/env python3.13

import sys
from pathlib import Path
from pprint import pprint

from frontend import lexer, parser

if __name__ == '__main__':
    file = Path(sys.argv[1])

    p = parser.Parser(lexer.tokenize(file))
    # for token in p.tokens._tokens:
    #     print(token)
    pprint(p.parse())
