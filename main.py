import sys
from pathlib import Path

from frontend import compiler
from backends import c99

if __name__ == '__main__':
	compiler.build(Path(sys.argv[1]), c99.Backend())
