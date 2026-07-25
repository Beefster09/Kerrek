#!/usr/bin/env python3.13

from pathlib import Path
import sys

from frontend import lexer

if __name__ == '__main__':
    file = Path(sys.argv[1])

    for token in lexer.tokenize(file):
        print(token)
