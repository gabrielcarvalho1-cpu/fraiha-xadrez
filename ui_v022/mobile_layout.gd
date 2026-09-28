extends CanvasLayer
## Mobile coordinates are CSS pixels, so fonts and touch targets retain their size.

var _portrait: ColorRect
var _window: Window
var _resize_pending := false
static var _active_cache := -1
static var _safe_insets := [12.0, 8.0, 12.0, 8.0]
static var _insets_size := Vector2.ZERO
static var _insets_dirty := true

static func active(_viewport: Viewport) -> bool:
    # Device classification does not change on rotation or while playing.
    # Stage calls this every frame, so cross the Web bridge only once.
    if _active_cache < 0:
        var mobile = "--mobile-test" in OS.get_cmdline_user_args() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
        if not mobile and OS.has_feature("web"):
            mobile = JavaScriptBridge.eval("(/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches))") == true
        _active_cache = 1 if mobile else 0
    return _active_cache == 1

static func _css_size(window: Window) -> Vector2i:
    if OS.has_feature("web"):
        var data = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(document.hidden ? [0, 0] : [window.innerWidth, window.innerHeight])")))
        if data is Array and data.size() == 2:
            return Vector2i(int(data[0]), int(data[1]))
    return window.size

static func safe_rect(viewport: Viewport) -> Rect2:
    var bounds = viewport.get_visible_rect()
    if not active(viewport):
        return bounds
    # Keep controls clear of rounded corners even when a browser reports zero insets.
    if OS.has_feature("web") and (_insets_dirty or _insets_size != bounds.size):
        var data = JSON.parse_string(str(JavaScriptBridge.eval("""
            (() => {
                if (document.hidden || !document.body) return null;
                let e = document.getElementById('fraiha-safe-area-probe');
                if (!e) {
                    e = document.createElement('div');
                    e.id = 'fraiha-safe-area-probe';
                    e.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
                    document.body.appendChild(e);
                }
                const s = getComputedStyle(e);
                const result = [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(v => parseFloat(v) || 0);
                return JSON.stringify(result);
            })()
        """)))
        if data is Array and data.size() == 4:
            _safe_insets = [12.0, 8.0, 12.0, 8.0]
            for i in range(4):
                _safe_insets[i] = maxf(_safe_insets[i], float(data[i]))
            _insets_size = bounds.size
            _insets_dirty = false
    return Rect2(bounds.position + Vector2(_safe_insets[0], _safe_insets[1]),
        Vector2(maxf(1.0, bounds.size.x - _safe_insets[0] - _safe_insets[2]), maxf(1.0, bounds.size.y - _safe_insets[1] - _safe_insets[3])))

static func _sync_window(window: Window) -> void:
    if window.get_meta("mobile_resize_busy", false):
        return
    var dimensions = _css_size(window)
    # Mobile browsers can temporarily report no size when switching apps.
    # Keep the last usable viewport instead of reallocating it at 1x1.
    if dimensions.x <= 0 or dimensions.y <= 0:
        return
    window.set_meta("mobile_resize_busy", true)
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
    if _window.get_meta("mobile_resize_busy", false):
        return
    _insets_dirty = true
    _resize_pending = true
    set_process(true)

func _process(_delta: float) -> void:
    # Drain a burst once per frame; never resize recursively from size_changed.
    if not _resize_pending:
        set_process(false)
        return
    _resize_pending = false
    set_process(false)
    _sync_window(_window)
    var dimensions = _window.get_visible_rect().size
    if dimensions.x <= 0 or dimensions.y <= 0:
        return
    _portrait.size = dimensions
    _portrait.visible = dimensions.y > dimensions.x

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(_window):
        _on_size_changed()

func _input(_event: InputEvent) -> void:
    if is_instance_valid(_portrait) and _portrait.visible:
        get_viewport().set_input_as_handled()
