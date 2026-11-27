@tool
extends EditorPlugin

var _export_plugin: DBZVRVoiceExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = DBZVRVoiceExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


class DBZVRVoiceExportPlugin extends EditorExportPlugin:
	const AAR_DEBUG_PATH := "res://addons/dbzvr_voice/bin/debug/dbzvr_voice-debug.aar"
	const AAR_RELEASE_PATH := "res://addons/dbzvr_voice/bin/release/dbzvr_voice-release.aar"

	func _get_name() -> String:
		return "DBZVRVoice"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var path: String = AAR_DEBUG_PATH if debug else AAR_RELEASE_PATH
		if FileAccess.file_exists(path):
			return PackedStringArray([path])
		return PackedStringArray()

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var path: String = AAR_DEBUG_PATH if debug else AAR_RELEASE_PATH
		if FileAccess.file_exists(path):
			return PackedStringArray([
				"com.alphacephei:vosk-android:0.3.47",
				"net.java.dev.jna:jna:5.13.0@aar",
			])
		return PackedStringArray()
