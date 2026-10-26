@tool
extends EditorPlugin
## R183 · no export Android (build Gradle): põe o SDK de voz da Agora como dependência e registra o plugin
## nativo com.fraiha.voice.FraihaVoicePlugin (código em android_plugin/fraiha_voice, copiado para android/build/src).

const AGORA := "io.agora.rtc:voice-sdk:4.5.2"
const BILLING := "com.android.billingclient:billing:8.0.0"   # R194 · compras pelo Google Play (só usadas no app da Play Store)
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
		return PackedStringArray([AGORA, BILLING])

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="org.godotengine.plugin.v2.FraihaVoice" android:value="com.fraiha.voice.FraihaVoicePlugin"/>'

	## R184d · fraihaxadrez://login abre o app (a página /app-login/done do servidor manda o navegador de volta
	## para o app depois do login com Google; o app já busca o login ao voltar para a frente).
	func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return APP_LINK

const APP_LINK := '<intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="fraihaxadrez" android:host="login"/></intent-filter>'
