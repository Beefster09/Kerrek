import sys
from pathlib import Path

from backends import c99
from frontend import compiler

if __name__ == "__main__":
    compiler.build(Path(sys.argv[1]), c99.Backend())
