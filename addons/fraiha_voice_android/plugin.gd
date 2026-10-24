@tool
extends EditorPlugin
## R183 · no export Android (build Gradle): põe o SDK de voz da Agora como dependência e registra o plugin
## nativo com.fraiha.voice.FraihaVoicePlugin (código em android_plugin/fraiha_voice, copiado para android/build/src).

const AGORA := "io.agora.rtc:voice-sdk:4.5.2"
var _exp: EditorExportPlugin

func _enter_tree():
	_exp = VoiceExport.new()
	add_export_plugin(_exp)

func _exit_tree():
	remove_export_plugin(_exp)
	_exp = null

class VoiceExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "FraihaVoiceAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([AGORA])

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="org.godotengine.plugin.v2.FraihaVoice" android:value="com.fraiha.voice.FraihaVoicePlugin"/>'
