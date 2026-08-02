
from frontend import ast

def validate(node: ast.Node):
	"""does all of the core validation of the code:
	- type checking
	- type inference
	- unit analysis
	- value label provenance checking
	- capability tracking
	"""
