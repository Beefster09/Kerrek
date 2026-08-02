
from frontend import ast

def validate(node: ast.TopLevelDeclaration):
	"""does all of the core validation of the code:
	- type checking
	- type inference
	- unit analysis
	- value label provenance checking
	- capability tracking
	"""
	match node:
		case ast.GlobalConstant():
			pass

		case ast.GlobalVariable():
			pass

		case ast.FuncDefinition():
			pass
