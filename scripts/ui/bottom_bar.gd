class_name BottomBar
extends HBoxContainer
## 底部按钮：说明书、免责声明（弹窗），以及下载器链接。

const UiKitScript = preload("res://scripts/ui/ui_kit.gd")
const InfoTextsScript = preload("res://scripts/ui/info_texts.gd")
const DOWNLOADER_URL := "https://github.com/glgl6688/gl-MC-downloader/"

var _manual_dialog: AcceptDialog
var _disclaimer_dialog: AcceptDialog
var _views := {}
var _built := false


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_BEGIN

	var manual_btn := UiKitScript.button("说明书")
	manual_btn.custom_minimum_size.x = 110
	manual_btn.pressed.connect(func() -> void: _show_doc(_manual_dialog, "使用说明书", InfoTextsScript.manual()))
	add_child(manual_btn)

	var disclaimer_btn := UiKitScript.button("免责声明")
	disclaimer_btn.custom_minimum_size.x = 110
	disclaimer_btn.pressed.connect(func() -> void: _show_doc(_disclaimer_dialog, "免责声明", InfoTextsScript.disclaimer()))
	add_child(disclaimer_btn)

	var downloader_btn := UiKitScript.button("下载器链接")
	downloader_btn.custom_minimum_size.x = 120
	downloader_btn.tooltip_text = DOWNLOADER_URL
	downloader_btn.pressed.connect(_open_downloader)
	add_child(downloader_btn)
	add_child(UiKitScript.spacer(true))

	_manual_dialog = _make_dialog("使用说明书", InfoTextsScript.manual())
	_disclaimer_dialog = _make_dialog("免责声明", InfoTextsScript.disclaimer())


func _make_dialog(title: String, text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.min_size = Vector2i(860, 640)
	dialog.get_ok_button().text = "关闭"
	var view := RichTextLabel.new()
	view.bbcode_enabled = true
	view.selection_enabled = true
	view.fit_content = false
	view.scroll_following = false
	view.custom_minimum_size = Vector2(820, 560)
	view.text = text
	dialog.add_child(view)
	add_child(dialog)
	_views[dialog] = view
	return dialog


func _show_doc(dialog: AcceptDialog, title: String, text: String) -> void:
	if dialog == null:
		return
	var view: RichTextLabel = _views.get(dialog, null)
	if view != null:
		view.text = text
	dialog.title = title
	dialog.popup_centered(Vector2i(880, 660))


func _open_downloader() -> void:
	var err := OS.shell_open(DOWNLOADER_URL)
	if err != OK:
		LogManager.error("无法打开下载器链接：%s（%s）" % [DOWNLOADER_URL, error_string(err)])
