from pathlib import Path
from collections import deque

from frontend import ast, lexer
from frontend import parser
from frontend.parser import Parser


class Resolver:
	def __init__(self, project_root: Path = Path.cwd()):
		self.project_root = project_root
		self.modules: dict[Path, ast.Module] = {}

	def require(self, path: Path) -> ast.Module:
		"""Resolves imported modules and parses them if missing
		"""
		path = path.absolute()

		if path in self.modules:
			return self.modules[path]

		module = parser.load(path)
		self.modules[path] = module

		for imp in module.imports:
			self.require(imp.get_filepath())  # TODO

		return module

	def resolve_names(self):
		"""Resolves qualified names to point to their definitions
		"""

	def _resolve_names(self, module: ast.Module, node: ast.Node):
		"""Resolves qualified names to point to their definitions
		"""

	def canonicalize_units(self):
		"""Give unique ids to all base units and simplify compound units
		"""
