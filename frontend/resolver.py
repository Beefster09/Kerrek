from frontend import ast


class SymbolTable:
	pass


def resolve_imports(symbols: SymbolTable, file: ast.File):
	"""Resolves imported modules and parses them if missing
	"""


def resolve_names(symbols: SymbolTable, current_file: ast.File, node: ast.Node):
	"""Resolves qualified names to point to their definitions
	"""


def canonicalize_units(symbols: SymbolTable, node: ast.Node):
	"""Give unique ids to all base units and simplify compound units
	"""
