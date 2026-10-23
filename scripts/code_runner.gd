## Runs a learner's typed GDScript against a test list, for real, inside the
## running engine: the learner's code is compiled on the fly with GDScript.new()
## and actually executed. No text matching, no simulated interpreter.
##
## Known limitation: GDScript has no try/catch. A runtime error in the learner's
## code (e.g. an out-of-range index) is reported by the engine as a non-fatal
## script error and the call returns null, which just shows up as a failed test
## rather than a caught exception. There is also no execution timeout, so a
## learner who writes an infinite loop will hang the tab until it's reloaded.
class_name CodeRunner
extends RefCounted

## Compiles `expr_src` as the body of a throwaway function and returns its value.
## Used both to turn a test's literal text ("[3]", "Vector2(1,2)", ...) into a
## real value, and to evaluate a "c" check expression with `r` bound to the result.
static func eval_expr(expr_src: String, extra_vars: Dictionary = {}) -> Dictionary:
	var preamble := ""
	for key in extra_vars:
		preamble += "var %s = %s\n" % [key, _literal(extra_vars[key])]
	var src := "func _eval():\n\t%s\n\treturn %s" % [preamble.replace("\n", "\n\t"), expr_src]
	var script := GDScript.new()
	script.source_code = src
	var err := script.reload()
	if err != OK:
		return {"ok": false, "err": "could not evaluate: %s" % expr_src}
	var instance = script.new()
	var value = instance.call("_eval")
	return {"ok": true, "value": value}

static func _literal(v) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is String:
		return "\"%s\"" % v.c_escape()
	if v is Vector2:
		return "Vector2(%s, %s)" % [v.x, v.y]
	if v is Vector3:
		return "Vector3(%s, %s, %s)" % [v.x, v.y, v.z]
	if v is Array:
		var parts := []
		for item in v:
			parts.append(_literal(item))
		return "[%s]" % ", ".join(parts)
	if v is Dictionary:
		var parts := []
		for k in v:
			parts.append("%s: %s" % [_literal(k), _literal(v[k])])
		return "{%s}" % ", ".join(parts)
	return str(v)

## Approximate equality that tolerates float rounding and recurses into
## Arrays/Dictionaries/Vectors the way the quiz's worked examples expect.
static func eq(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 0.000001 * maxf(1.0, absf(float(b)))
	if a is Vector2 and b is Vector2:
		return a.distance_to(b) <= 0.000001
	if a is Vector3 and b is Vector3:
		return a.distance_to(b) <= 0.000001
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not eq(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not eq(a[k], b[k]):
				return false
		return true
	return a == b

static func fmt(v) -> String:
	if v == null:
		return "null"
	if v is String:
		return "\"%s\"" % v
	return str(v)

## code: the learner's full script source (one or more top-level funcs).
## func_name: the function under test.
## tests: Array of Dictionaries, each either {"a":argsLiteral,"e":expectedLiteral}
##        or {"a":argsLiteral,"c":checkExprUsingR}, optionally with "h":1 for hidden.
static func run_tests(code: String, func_name: String, tests: Array) -> Dictionary:
	var script := GDScript.new()
	script.source_code = code
	var err := script.reload()
	if err != OK:
		return {"ok": false, "err": "Your code has an error and could not compile.", "results": []}
	var instance = script.new()
	if not instance.has_method(func_name):
		return {"ok": false, "err": "I could not find a function named %s. Keep that exact name." % func_name, "results": []}

	var results := []
	var all_pass := true
	for t in tests:
		var row := {"hidden": t.get("h", 0) == 1, "pass": false}
		var args_eval := eval_expr(t["a"])
		if not args_eval["ok"]:
			row["err"] = "internal test error"
			results.append(row)
			all_pass = false
			continue
		var args: Array = args_eval["value"]
		row["a"] = t["a"]
		var got = instance.callv(func_name, args)
		row["got"] = fmt(got)
		if t.has("c"):
			row["e"] = "a result that passes: %s" % t["c"]
			var check := eval_expr(t["c"], {"r": got})
			row["pass"] = check["ok"] and bool(check["value"])
		else:
			var exp_eval := eval_expr(t["e"])
			row["e"] = fmt(exp_eval.get("value"))
			row["pass"] = exp_eval["ok"] and eq(got, exp_eval["value"])
		if not row["pass"]:
			all_pass = false
		results.append(row)
	return {"ok": all_pass, "err": null, "results": results}
