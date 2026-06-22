extends Node
class_name GdliEval
## Execution context for `eval` scripts (single expressions, statement blocks, and full files). In scope:
##   root        — the scene root (game current_scene / editor edited scene)
##   argv        — tokens passed after `eval @handle <args…>`
##   gdli(cmd)   — invoke ANY gdli verb by its CLI string, returning its raw result (verb reuse / macros)
## Inline code gets this context auto-generated. A full file needs no base — if it declares none, this
## one is injected — just write your funcs incl. an entry (`func run():`, or name it via `--entry`). The
## entry may take `argv` (`func run(argv):`) or read it ambiently. Same `gdli("…")` strings as the CLI.

var root: Node
var argv: Array = []
var _srv  # the GdliServer (untyped to avoid a cyclic class reference)

func gdli(cmd: String) -> Variant:
	return _srv.call_gdli_string(cmd)
