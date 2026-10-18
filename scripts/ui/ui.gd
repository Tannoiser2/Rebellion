class_name UI
extends RefCounted
## Stile grafico: console olografica su fondo stellato. Pannelli grigio acciaio come le cornici
## delle carte, azzurro ologramma per le scelte, rosso per l'Alleanza e blu-acciaio per l'Impero.
## Titoli in Orbitron, testo in Exo 2, numeri e cronaca in Share Tech Mono (tutti con licenza OFL).

const BG := Color("#05070d")
const PANEL := Color(0.055, 0.075, 0.115, 0.93)
const PANEL2 := Color(0.09, 0.12, 0.17, 0.96)
const STEEL := Color("#2c3c52")
const STEEL_L := Color("#4f6680")
const HOLO := Color("#7fd8ff")
const HOLO_D := Color("#2a6f92")
const TEXT := Color("#e6edf5")
const DIM := Color("#8ea3b8")
const REBEL := Color("#e8553e")
const REBEL_D := Color("#7a2416")
const EMPIRE := Color("#62a6ff")
const EMPIRE_D := Color("#1d3d66")
const GOLD := Color("#f2c14e")
const GOOD := Color("#71e38d")
const BAD := Color("#ff6b5e")

static var _tex := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font
static var font_mono: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/Orbitron-Bold.woff2")
	font_body = load("res://assets/fonts/Exo2-Regular.woff2")
	font_bold = load("res://assets/fonts/Exo2-SemiBold.woff2")
	font_italic = load("res://assets/fonts/Exo2-Italic.woff2")
	font_mono = load("res://assets/fonts/ShareTechMono.woff2")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func fcolor(f: String) -> Color:
	return REBEL if f == "R" else EMPIRE


static func fcolor_d(f: String) -> Color:
	return REBEL_D if f == "R" else EMPIRE_D


static func leader_tex(n: String) -> Texture2D:
	return tex("res://assets/leaders/%s.jpg" % _slug(n))


static func unit_icon(t: String) -> Texture2D:
	return tex("res://assets/tokens/u_%s.png" % _slug(t))


static func _slug(s: String) -> String:
	var out := ""
	var prev := false
	for ch in s.to_lower().replace("'", ""):
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if ok:
			out += ch
			prev = false
		elif not prev:
			out += "_"
			prev = true
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


# ------------------------------------------------------------------ stili

static func box(bg := PANEL, border := STEEL, bw := 1, radius := 3, margin := 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## Pannello olografico: fondo scuro, bordo d'acciaio e una linea luminosa in alto.
static func holo(margin := 14.0, accent := HOLO) -> StyleBoxFlat:
	var sb := box(PANEL, STEEL, 1, 4, margin)
	sb.border_width_top = 2
	sb.border_color = STEEL_L
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	sb.expand_margin_top = 0
	sb.border_blend = false
	sb.set("border_color", accent.darkened(0.35))
	return sb


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "CheckBox", "OptionButton"]:
		t.set_font("font", cls, font_bold)
		t.set_font_size("font_size", cls, 20)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.55, 0.6, 0.66, 0.6))
	t.set_stylebox("normal", "Button", _btn(PANEL2, STEEL_L))
	t.set_stylebox("hover", "Button", _btn(Color(0.12, 0.2, 0.28, 0.98), HOLO))
	t.set_stylebox("pressed", "Button", _btn(HOLO_D, HOLO))
	t.set_stylebox("disabled", "Button", _btn(Color(0.07, 0.08, 0.1, 0.8), STEEL))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", holo())
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.05, 0.08, 0.95), STEEL_L, 1, 3, 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.05, 0.08, 0.95), HOLO, 1, 3, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font("font", "LineEdit", font_mono)
	t.set_font("normal_font", "RichTextLabel", font_body)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("italics_font", "RichTextLabel", font_italic)
	t.set_font("mono_font", "RichTextLabel", font_mono)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.05, 0.09, 0.97), HOLO_D, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font_body)
	t.set_font_size("font_size", "TooltipLabel", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.3, 0.4, 0.6)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.25)
	t.set_stylebox("scroll", "VScrollBar", sb2)
	return t


static func _btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := box(bg, border, 1, 3, 10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Colora un pulsante (azzurro = scelta principale, o colore della fazione).
static func tint(b: Button, col: Color) -> Button:
	b.add_theme_stylebox_override("normal", _btn(col.darkened(0.55), col))
	b.add_theme_stylebox_override("hover", _btn(col.darkened(0.3), col.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", _btn(col.darkened(0.1), Color.WHITE))
	return b


static func primary(b: Button) -> Button:
	return tint(b, HOLO)


# ------------------------------------------------------------------ elementi

static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 30, col := TEXT) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	return l


static func wrap(text: String, size := 19, width := 400.0, col := TEXT) -> Label:
	var l := label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func rich(text: String, size := 19, width := 400.0) -> RichTextLabel:
	init_fonts()
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size.x = width
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.text = text
	return r


static func button(text: String, w := 0.0, h := 46.0, size := 20) -> Button:
	init_fonts()
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func panel(margin := 14.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", holo(margin))
	return p


static func hsep(col := STEEL) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(0, 1)
	return c


## Icona testuale per le abilità e le facce dei dadi (le carte le stampano come simboli).
const SKILL_COLOR := {"diplomazia": Color("#e8b84a"), "intel": Color("#58c6c2"), "logistica": Color("#a7865c"), "opspec": Color("#d0503c")}
const SKILL_SHORT := {"diplomazia": "DIP", "intel": "INT", "logistica": "LOG", "opspec": "OPS"}


## Testo delle carte con i segnaposto ([diplomazia], [colpo]…) resi leggibili.
static func card_text(t: String) -> String:
	var rep := {
		"[diplomazia]": "[color=#e8b84a]◆diplomazia[/color]", "[intel]": "[color=#58c6c2]◆intelligence[/color]",
		"[logistica]": "[color=#c4a37a]◆logistica[/color]", "[opspec]": "[color=#e06a55]◆operazioni speciali[/color]",
		"[colpo]": "[color=#ffd27a]✸[/color]", "[colpo_diretto]": "[color=#ffd27a]✸✸[/color]", "[speciale]": "[color=#ffd27a]✦[/color]",
		"[triangolo_blu]": "[color=#62a6ff]▲[/color]", "[cerchio_blu]": "[color=#62a6ff]●[/color]", "[quadrato_blu]": "[color=#62a6ff]■[/color]",
		"[triangolo_arancio]": "[color=#f0a040]▲[/color]", "[cerchio_arancio]": "[color=#f0a040]●[/color]", "[quadrato_arancio]": "[color=#f0a040]■[/color]",
		"[triangolo]": "▲", "[cerchio]": "●", "[quadrato]": "■", "[triangolo_nero]": "▲", "[cerchio_nero]": "●", "[dado]": "⚄",
	}
	for k in rep:
		t = t.replace(k, rep[k])
	return t


## Testo senza BBCode, per pulsanti ed etichette semplici.
static func plain_text(t: String) -> String:
	var rep := {"[colpo_diretto]": "✸✸", "[colpo]": "✸", "[speciale]": "✦", "[diplomazia]": "diplomazia", "[intel]": "intelligence",
		"[logistica]": "logistica", "[opspec]": "operazioni speciali", "[triangolo]": "▲", "[cerchio]": "●", "[quadrato]": "■",
		"[triangolo_blu]": "▲", "[cerchio_blu]": "●", "[quadrato_blu]": "■", "[triangolo_arancio]": "▲", "[cerchio_arancio]": "●",
		"[quadrato_arancio]": "■", "[triangolo_nero]": "▲", "[cerchio_nero]": "●", "[dado]": "⚄", "[b]": "", "[/b]": ""}
	for k in rep:
		t = t.replace(k, rep[k])
	return t
