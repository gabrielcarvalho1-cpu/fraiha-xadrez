extends CanvasLayer
## Mobile coordinates are CSS pixels, so fonts and touch targets retain their size.

var _portrait: ColorRect
var _window: Window

static func active(_viewport: Viewport) -> bool:
    if "--mobile-test" in OS.get_cmdline_user_args():
        return true
    if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
        return true
    if OS.has_feature("web"):
        return JavaScriptBridge.eval("(/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches))") == true
    return false

static func _css_size(window: Window) -> Vector2i:
    if OS.has_feature("web"):
        var data = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify([window.innerWidth, window.innerHeight])")))
        if data is Array and data.size() == 2:
            return Vector2i(maxi(1, int(data[0])), maxi(1, int(data[1])))
    return window.size

static func safe_rect(viewport: Viewport) -> Rect2:
    var bounds = viewport.get_visible_rect()
    if not active(viewport):
        return bounds
    # Keep controls clear of rounded corners even when a browser reports zero insets.
    var insets = [12.0, 8.0, 12.0, 8.0]
    if OS.has_feature("web"):
        var data = JSON.parse_string(str(JavaScriptBridge.eval("""
            (() => {
                const e = document.createElement('div');
                e.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
                document.body.appendChild(e);
                const s = getComputedStyle(e);
                const result = [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(v => parseFloat(v) || 0);
                e.remove();
                return JSON.stringify(result);
            })()
        """)))
        if data is Array and data.size() == 4:
            for i in range(4):
                insets[i] = maxf(insets[i], float(data[i]))
    return Rect2(bounds.position + Vector2(insets[0], insets[1]),
        Vector2(maxf(1.0, bounds.size.x - insets[0] - insets[2]), maxf(1.0, bounds.size.y - insets[1] - insets[3])))

static func _sync_window(window: Window) -> void:
    if window.get_meta("mobile_resize_busy", false):
        return
    window.set_meta("mobile_resize_busy", true)
    var dimensions = _css_size(window)
    if window.content_scale_size != dimensions:
        window.content_scale_size = dimensions
    window.set_meta("mobile_resize_busy", false)

static func configure_window(window: Window) -> void:
    if not active(window) or window.has_meta("mobile_layout_configured"):
        return
    window.set_meta("mobile_layout_configured", true)
    _sync_window(window)
    var helper: CanvasLayer = load("res://ui_v022/mobile_layout.gd").new()
    helper.name = "MobileOrientation"
    helper.layer = 200
    window.add_child.call_deferred(helper)

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _window = get_window()
    _portrait = ColorRect.new()
    _portrait.color = Color("101b17")
    _portrait.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_portrait)
    var instruction = Label.new()
    instruction.text = "GIRE O CELULAR PARA JOGAR"
    instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    instruction.add_theme_font_size_override("font_size", 28)
    instruction.add_theme_color_override("font_color", Color("f4ce7f"))
    instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _portrait.add_child(instruction)
    instruction.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    instruction.offset_left = 24
    instruction.offset_right = -24
    _window.size_changed.connect(_on_size_changed)
    _on_size_changed()

func _on_size_changed() -> void:
    _sync_window(_window)
    var dimensions = _window.get_visible_rect().size
    _portrait.size = dimensions
    _portrait.visible = dimensions.y > dimensions.x

func _input(_event: InputEvent) -> void:
    if is_instance_valid(_portrait) and _portrait.visible:
        get_viewport().set_input_as_handled()
