extends Control
## Godot Ladder: the whole app, one script, full-rebuild-on-every-render,
## the same shape as ml-ladder's single index.html. State lives in S and is
## persisted via SaveData. QuestionBank/ExerciseBank/CodeRunner are global
## class_names (no preload needed).

const PER := 8  # questions per level that must be mastered to level up

const BG := Color("0f1419")
const CARD_BG := Color("18202a")
const TEXT_COL := Color("e6e6e6")
const SUB_COL := Color("8fa1b3")
const GREEN := Color("4cc38a")
const RED := Color("e05d6f")
const BLUE := Color("2f6fed")
const BTN_BG := Color("243242")
const BTN_BORDER := Color("33475c")
const IDK_BG := Color("2a2433")
const IDK_BORDER := Color("4a3d5c")
const IDK_TEXT := Color("c9b8e0")
const OK_BG := Color("17402c")
const BAD_BG := Color("47202a")
const WHY_BG := Color("13261e")
const WHY_BAD_BG := Color("2a161b")
const WHY_IDK_BG := Color("221b2e")
const LOCK_COL := Color(1, 1, 1, 0.45)

var S: Dictionary
var cur: Dictionary = {}
var answered := false

var root_box: VBoxContainer
var opt_buttons: Array = []
var fb_box: VBoxContainer
var hint_label: Label

# Web-only: Godot's own TextEdit doesn't receive text from the mobile OS
# keyboard in Web exports (engine bug, godotengine/godot#108355 — the canvas
# losing DOM focus to the virtual keyboard's hidden input also clears the
# engine's internal text focus, so push_text_input becomes a no-op). The
# workaround is a real, fixed-position HTML <textarea> pinned to the
# viewport, so the browser's native keyboard and text handling do the work
# instead — same idea as ml-ladder's plain HTML textarea, just injected.
var current_ex_id: String = ""
var web_overlay_active := false

func _ready() -> void:
	S = SaveData.load_state()
	_normalize_state()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root_box)
	if _is_web():
		var cb := JavaScriptBridge.create_callback(_on_web_overlay_input)
		JavaScriptBridge.get_interface("window").__godot_overlay_cb = cb
		get_viewport().size_changed.connect(_on_viewport_resized)
	render()

func _is_web() -> bool:
	return OS.get_name() == "Web"

func _on_viewport_resized() -> void:
	if web_overlay_active:
		render()

func _remove_web_overlay() -> void:
	if web_overlay_active:
		JavaScriptBridge.eval("window.hideCodeOverlay();", true)
		web_overlay_active = false

func _on_web_overlay_input(args: Array) -> void:
	if current_ex_id != "" and args.size() > 0:
		S.drafts[current_ex_id] = String(args[0])

func _show_web_overlay(draft: String) -> void:
	# The #godot-code-overlay textarea is a real, static element baked
	# into html_shell.html from page load (see export_presets.cfg's
	# custom_html_shell) -- not created at runtime via eval, which kept
	# producing an invisible box due to timing issues on the Godot side.
	# This just shows/fills/focuses an element that already exists.
	JavaScriptBridge.eval("window.showCodeOverlay(%s);" % JSON.stringify(draft), true)
	web_overlay_active = true

func _normalize_state() -> void:
	S.level = int(S.level)
	S.top = int(S.top)
	S.n = int(S.n)
	S.stats.ans = int(S.stats.ans)
	S.stats.right = int(S.stats.right)
	S.stats.idk = int(S.stats.idk)
	S.done = bool(S.done)
	var fixed_due := []
	for entry in S.due:
		fixed_due.append({"id": int(entry["id"]), "at": int(entry["at"])})
	S.due = fixed_due

func save() -> void:
	SaveData.save_state(S)

func clear_root() -> void:
	_remove_web_overlay()
	for c in root_box.get_children():
		root_box.remove_child(c)
		c.queue_free()
	opt_buttons = []
	fb_box = null

# ---------------------------------------------------------------- styling --

func style_panel(p: PanelContainer, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)

func make_card() -> VBoxContainer:
	var panel := PanelContainer.new()
	style_panel(panel, CARD_BG)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	return vb

func make_label(text: String, size: int = 16, color: Color = TEXT_COL, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func style_button(btn: Button, bg: Color, border: Color, text_col: Color = TEXT_COL) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate()
	hover.bg_color = bg.lightened(0.08)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate()
	pressed.bg_color = bg.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := sb.duplicate()
	disabled.bg_color = bg
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_disabled_color", text_col)

func make_button(text: String, variant: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match variant:
		"idk":
			style_button(b, IDK_BG, IDK_BORDER, IDK_TEXT)
		"ok":
			style_button(b, OK_BG, GREEN)
		"bad":
			style_button(b, BAD_BG, RED)
		"go":
			style_button(b, BLUE, BLUE)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		"lock":
			style_button(b, BTN_BG, BTN_BORDER, LOCK_COL)
		_:
			style_button(b, BTN_BG, BTN_BORDER)
	return b

func make_why_panel(text: String, variant: String = "ok") -> PanelContainer:
	var panel := PanelContainer.new()
	var bg := WHY_BG
	if variant == "bad":
		bg = WHY_BAD_BG
	elif variant == "idk":
		bg = WHY_IDK_BG
	style_panel(panel, bg)
	var lbl := make_label(text, 15, TEXT_COL)
	panel.add_child(lbl)
	return panel

# ------------------------------------------------------------ data helpers --

func ids_at(level: int) -> Array:
	var r := []
	for i in range(QuestionBank.BANK.size()):
		if QuestionBank.BANK[i]["l"] == level:
			r.append(i)
	return r

func bx(i: int) -> int:
	return int(S.box.get(str(i), -1))

func mastered(level: int) -> int:
	var c := 0
	for id in ids_at(level):
		if bx(id) >= 2:
			c += 1
	return c

func pick() -> int:
	for k in range(S.due.size()):
		if S.due[k]["at"] <= S.n:
			var d = S.due[k]
			S.due.remove_at(k)
			return d["id"]
	var ids := ids_at(S.level)
	var fresh := []
	for id in ids:
		if bx(id) < 0:
			fresh.append(id)
	if fresh.size() > 0 and randf() < 0.85:
		return fresh[randi() % fresh.size()]
	var pool := []
	for k in range(QuestionBank.BANK.size()):
		if QuestionBank.BANK[k]["l"] <= S.level and bx(k) >= 0 and bx(k) < 9:
			pool.append(k)
	var weak := []
	for id in ids:
		if bx(id) >= 0 and bx(id) < 2:
			weak.append(id)
	if weak.size() > 0 and randf() < 0.6:
		return weak[randi() % weak.size()]
	if pool.size() > 0:
		return pool[randi() % pool.size()]
	if fresh.size() > 0:
		return fresh[randi() % fresh.size()]
	return ids[randi() % ids.size()]

func schedule(id: int, gap: int) -> void:
	S.due.append({"id": id, "at": S.n + gap})

func exercises_for(level: int) -> Array:
	var r := []
	for ex in ExerciseBank.EX:
		if ex["l"] == level:
			r.append(ex)
	return r

func ex_solved(id: String) -> bool:
	return S.code.has(id) and S.code[id].get("ok", false)

func level_done(level: int) -> bool:
	for ex in exercises_for(level):
		if not ex_solved(ex["id"]):
			return false
	return true

func unlocked(level: int) -> bool:
	return level == 1 or level <= S.top or level_done(level - 1)

func next_ex() -> Dictionary:
	for ex in ExerciseBank.EX:
		if not ex_solved(ex["id"]) and unlocked(ex["l"]):
			return ex
	return {}

func ex_by_id(id: String) -> Dictionary:
	for ex in ExerciseBank.EX:
		if ex["id"] == id:
			return ex
	return {}

# ------------------------------------------------------------------ render --

func render() -> void:
	clear_root()
	if S.mode == "code":
		render_code()
	else:
		render_quiz()

func add_header() -> void:
	root_box.add_child(make_label("Godot Ladder", 22, TEXT_COL))
	root_box.add_child(make_label("Endless questions. \"I don't know\" is always a fine answer.", 14, SUB_COL))

	var m := mastered(S.level)
	var meta1 := HBoxContainer.new()
	var lv_lbl := make_label("Level %d of %d: %s" % [S.level, QuestionBank.LEVELS.size(), QuestionBank.LEVELS[S.level - 1]], 14, SUB_COL, false)
	lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta1.add_child(lv_lbl)
	meta1.add_child(make_label("%d/%d mastered" % [m, PER], 14, SUB_COL, false))
	root_box.add_child(meta1)

	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = 100.0 * m / PER
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color("1f2933")
	bg_sb.corner_radius_top_left = 5
	bg_sb.corner_radius_top_right = 5
	bg_sb.corner_radius_bottom_left = 5
	bg_sb.corner_radius_bottom_right = 5
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = GREEN
	fill_sb.corner_radius_top_left = 5
	fill_sb.corner_radius_top_right = 5
	fill_sb.corner_radius_bottom_left = 5
	fill_sb.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("background", bg_sb)
	bar.add_theme_stylebox_override("fill", fill_sb)
	root_box.add_child(bar)

	var meta2 := HBoxContainer.new()
	var stats_lbl := make_label("Answered %d · correct %d · unsure %d" % [S.stats.ans, S.stats.right, S.stats.idk], 13, SUB_COL, false)
	stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta2.add_child(stats_lbl)
	var menu_btn := Button.new()
	menu_btn.text = "levels"
	menu_btn.flat = true
	menu_btn.add_theme_color_override("font_color", Color("6aa9ff"))
	menu_btn.pressed.connect(func(): menu())
	meta2.add_child(menu_btn)
	root_box.add_child(meta2)

	add_tabs()

func add_tabs() -> void:
	var solved := 0
	for ex in ExerciseBank.EX:
		if ex_solved(ex["id"]):
			solved += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tq := make_button("Quiz", "go" if S.mode == "quiz" else "")
	tq.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tq.pressed.connect(func(): S.mode = "quiz"; S.view = "list"; save(); render())
	var tc := make_button("Code (%d/%d)" % [solved, ExerciseBank.EX.size()], "go" if S.mode == "code" else "")
	tc.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.pressed.connect(func(): S.mode = "code"; S.view = "list"; save(); render())
	row.add_child(tq)
	row.add_child(tc)
	root_box.add_child(row)

# -------------------------------------------------------------------- quiz --

func render_quiz() -> void:
	add_header()
	if cur.is_empty():
		var order := [0, 1, 2, 3]
		order.shuffle()
		cur = {"id": pick(), "order": order}
		answered = false
	var q: Dictionary = QuestionBank.BANK[cur.id]
	var vb := make_card()
	if bx(cur.id) >= 0 and bx(cur.id) < 2:
		vb.add_child(make_label("asking again · level %d" % q["l"], 12, SUB_COL, false))
	else:
		vb.add_child(make_label("level %d" % q["l"], 12, SUB_COL, false))
	vb.add_child(make_label(q["q"], 19, TEXT_COL))
	opt_buttons = []
	for i in range(4):
		var opt_idx: int = cur.order[i]
		var b := make_button(q["o"][opt_idx])
		b.set_meta("opt", opt_idx)
		b.pressed.connect(func(): answer(opt_idx))
		vb.add_child(b)
		opt_buttons.append(b)
	var idk_btn := make_button("I don't know (explain it to me)", "idk")
	idk_btn.pressed.connect(func(): answer(-1))
	vb.add_child(idk_btn)
	opt_buttons.append(idk_btn)
	fb_box = VBoxContainer.new()
	fb_box.add_theme_constant_override("separation", 8)
	vb.add_child(fb_box)

func answer(o: int) -> void:
	if answered:
		return
	answered = true
	var id: int = cur.id
	var q: Dictionary = QuestionBank.BANK[id]
	var b := bx(id)
	var good := o == 0
	var idk := o == -1
	S.n += 1
	S.stats.ans += 1

	for btn in opt_buttons:
		btn.disabled = true
		if not btn.has_meta("opt"):
			continue
		var v: int = btn.get_meta("opt")
		if v == 0:
			style_button(btn, OK_BG, GREEN)
		elif v == o and not good:
			style_button(btn, BAD_BG, RED)

	var msg := ""
	var variant := "ok"
	if good:
		S.stats.right += 1
		if b < 0:
			S.box[str(id)] = 2
		else:
			S.box[str(id)] = min(9, b + 1)
		if b >= 0 and b < 2:
			schedule(id, 10)
		msg = "Correct. "
	else:
		S.box[str(id)] = 0
		schedule(id, 3)
		if idk:
			S.stats.idk += 1
			variant = "idk"
			msg = "No problem, that is how you learn it. "
		else:
			variant = "bad"
			msg = "Not quite. "
		msg += "The answer: %s. " % q["o"][0]

	if not good:
		msg += "\nThis one will come back in a few questions."
	fb_box.add_child(make_why_panel(msg + "\n" + q["w"], variant))

	var lvlmsg := check_level_up()
	if lvlmsg != "":
		fb_box.add_child(make_why_panel(lvlmsg, "ok"))

	var next_btn := make_button("Next question", "go")
	next_btn.pressed.connect(func(): cur = {}; save(); render())
	fb_box.add_child(next_btn)
	save()

func check_level_up() -> String:
	var nlev := QuestionBank.LEVELS.size()
	if S.level < nlev and mastered(S.level) >= PER - 1:
		S.level += 1
		if S.level > S.top:
			S.top = S.level
		return "Level up! Now level %d: %s." % [S.level, QuestionBank.LEVELS[S.level - 1]]
	if S.level == nlev and mastered(nlev) >= PER - 1 and not S.done:
		S.done = true
		return "You cleared all %d levels. The questions keep coming, mixed from every level, so nothing fades." % nlev
	return ""

func menu() -> void:
	clear_root()
	root_box.add_child(make_label("Levels", 22, TEXT_COL))
	var list_vb := make_card()
	var nlev := QuestionBank.LEVELS.size()
	for i in range(1, nlev + 1):
		var marker := "▶ " if i == S.level else ""
		list_vb.add_child(make_label("%s%d. %s (%d/%d)" % [marker, i, QuestionBank.LEVELS[i - 1], mastered(i), PER], 14))

	var jump_vb := make_card()
	jump_vb.add_child(make_label("Jump to a level (your progress there is kept):", 13, SUB_COL))
	var opt := OptionButton.new()
	for i in range(1, nlev + 1):
		opt.add_item("%d. %s" % [i, QuestionBank.LEVELS[i - 1]], i)
	opt.select(S.level - 1)
	jump_vb.add_child(opt)
	var go_btn := make_button("Go", "go")
	go_btn.pressed.connect(func(): S.level = opt.get_item_id(opt.selected); cur = {}; save(); render())
	jump_vb.add_child(go_btn)
	var reset_btn := make_button("Reset all progress")
	reset_btn.pressed.connect(_on_reset_pressed)
	jump_vb.add_child(reset_btn)

	var back_btn := make_button("Back to questions", "go")
	back_btn.pressed.connect(func(): render())
	root_box.add_child(back_btn)

func _on_reset_pressed() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Erase all progress?"
	add_child(confirm)
	confirm.confirmed.connect(func():
		S = SaveData.default_state()
		cur = {}
		save()
		render())
	confirm.popup_centered()

# -------------------------------------------------------------------- code --

func render_code() -> void:
	if S.view != "list":
		var ex := ex_by_id(S.view)
		if not ex.is_empty():
			render_exercise(ex)
			return
	add_header()
	var intro := make_card()
	intro.add_child(make_label("Type real GDScript. Easy first, then harder, same levels as the quiz. Your code runs for real, right here in the engine. Finishing a level's exercises unlocks the next one (or level up in the Quiz).", 14, SUB_COL))

	var nx := next_ex()
	if not nx.is_empty():
		var cont := make_button("Continue: %s" % nx["title"], "go")
		cont.pressed.connect(func(): S.view = nx["id"]; save(); render())
		root_box.add_child(cont)

	var nlev := QuestionBank.LEVELS.size()
	for l in range(1, nlev + 1):
		var open := unlocked(l)
		var exs := exercises_for(l)
		var solved := 0
		var vb := make_card()
		var title := "Level %d: %s" % [l, QuestionBank.LEVELS[l - 1]]
		if not open:
			title += "  (locked: finish level %d code or quiz)" % (l - 1)
		vb.add_child(make_label(title, 15))
		for ex in exs:
			var ok := ex_solved(ex["id"])
			if ok:
				solved += 1
			var prefix := "✓ " if ok else ("▶ " if open else "\U0001F512 ")
			var b := make_button(prefix + ex["title"], "" if open else "lock")
			b.disabled = not open
			if open:
				var exid: String = ex["id"]
				b.pressed.connect(func(): S.view = exid; save(); render())
			vb.add_child(b)
		vb.add_child(make_label("%d/%d solved" % [solved, exs.size()], 13, SUB_COL, false))

func render_exercise(ex: Dictionary) -> void:
	add_header()
	var card := make_card()
	card.add_child(make_label(ex["title"], 19))
	card.add_child(make_label(ex["desc"], 14, SUB_COL))

	hint_label = make_label("", 13, IDK_TEXT)
	hint_label.visible = false
	var hint_btn := make_button("Show hint")
	hint_btn.pressed.connect(func():
		hint_label.text = ex["hint"]
		hint_label.visible = true)
	card.add_child(hint_btn)
	card.add_child(hint_label)

	var draft: String = S.drafts.get(ex["id"], ex["starter"])
	if _is_web():
		current_ex_id = ex["id"]
		card.add_child(make_label("Your code box is pinned near the bottom of the screen — scroll down to find it.", 13, SUB_COL))
		call_deferred("_show_web_overlay", draft)
	else:
		var code_edit := TextEdit.new()
		code_edit.text = draft
		code_edit.custom_minimum_size = Vector2(0, 220)
		code_edit.focus_mode = Control.FOCUS_ALL
		code_edit.mouse_filter = Control.MOUSE_FILTER_PASS
		code_edit.add_theme_font_size_override("font_size", 14)
		code_edit.add_theme_color_override("background_color", Color("0b0f14"))
		code_edit.add_theme_color_override("font_color", Color("d8e6f5"))
		card.add_child(code_edit)
		code_edit.text_changed.connect(func(): S.drafts[ex["id"]] = code_edit.text)
		code_edit.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				code_edit.grab_focus())
		code_edit.call_deferred("grab_focus")

	var results_box := VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 4)

	var run_btn := make_button("Run", "go")
	run_btn.pressed.connect(func():
		var code: String = S.drafts.get(ex["id"], ex["starter"])
		var r := CodeRunner.run_tests(code, ex["name"], ex["tests"])
		_render_results(results_box, r, ex)
		save())
	card.add_child(run_btn)
	card.add_child(results_box)

	var sol_code_label := make_label("", 14, Color("d8e6f5"))
	sol_code_label.visible = false
	var sol_why_label := make_label("", 14, TEXT_COL)
	sol_why_label.visible = false
	var sol_btn := make_button("Show solution")
	sol_btn.pressed.connect(func():
		sol_code_label.text = ex["sol"]
		sol_why_label.text = "Why this works:\n" + ex["why"]
		sol_code_label.visible = true
		sol_why_label.visible = true)
	card.add_child(sol_btn)
	card.add_child(sol_code_label)
	card.add_child(sol_why_label)

	var back_btn := make_button("Back to exercise list", "go")
	back_btn.pressed.connect(func(): S.view = "list"; save(); render())
	root_box.add_child(back_btn)

func _render_results(box: VBoxContainer, r: Dictionary, ex: Dictionary) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if r.get("err") != null:
		box.add_child(make_label(str(r["err"]), 13, RED))
		return
	var results: Array = r["results"]
	var p := 0
	for row in results:
		if row["pass"]:
			p += 1
	box.add_child(make_label("%d/%d tests pass" % [p, results.size()], 14, TEXT_COL))
	for row in results:
		if row["pass"]:
			box.add_child(make_label("✓ %s passed" % ("hidden test" if row["hidden"] else "test"), 13, GREEN))
		elif row["hidden"]:
			box.add_child(make_label("✗ A hidden test failed (it checks a tricky case).", 13, RED))
		else:
			box.add_child(make_label("✗ input %s  expected %s  you got %s" % [row.get("a", ""), row.get("e", ""), row.get("got", "")], 13, RED))
	if r["ok"]:
		S.code[ex["id"]] = {"ok": true}
		var nx := next_ex()
		if not nx.is_empty():
			var cont := make_button("Solved! Continue: %s" % nx["title"], "go")
			var nxid: String = nx["id"]
			cont.pressed.connect(func(): S.view = nxid; save(); render())
			box.add_child(cont)
		else:
			box.add_child(make_label("Solved! That's every exercise unlocked so far.", 14, GREEN))
