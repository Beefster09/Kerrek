
from frontend import ast

def check_types(node: ast.Node):
	"""checks types, units, and labels for logical soundness

	also infers types
	"""


def check_capabilities(node: ast.Node):
	"""checks that you don't call functions or mutate fields without
	having the proper authority to do so
	"""
