// R183 · FRAIHA Voice no APP ANDROID: ponte Godot ↔ Agora Android SDK (só áudio).
// O GDScript (voice/agora_native_provider.gd) chama estes métodos; tudo o que acontece volta pelo sinal
// "voice_event" com um JSON igual ao do provedor da Web ({ev, seq, ...}), então o FraihaVoice não muda.
// Sem token no log. O token vem do servidor do jogo (voice_join), nunca é gerado aqui.
// Copiado para android/build/src pelo tools/android/montar_build_gradle.py (a pasta android/ é gerada).
package com.fraiha.voice

import android.util.Log
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject

class FraihaVoicePlugin(godot: Godot) : GodotPlugin(godot) {
    private var engine: RtcEngine? = null
    private var appIdUsed = ""
    private var seq = 0
    private var joined = false
    private var muted = false
    private var speakerMuted = false
    private val remotes = linkedSetOf<Int>()
    private val mutedUids = hashSetOf<Int>()
    private var lastSpeaking = ""

    override fun getPluginName() = "FraihaVoice"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(SignalInfo("voice_event", String::class.java))

    private fun emit(ev: String, data: JSONObject = JSONObject(), withSeq: Boolean = true) {
        data.put("ev", ev)
        if (withSeq) data.put("seq", seq)
        val s = data.toString()
        runOnRenderThread { emitSignal("voice_event", s) }
    }

    private fun uids(): JSONArray {
        val a = JSONArray()
        for (u in remotes.sorted()) a.put(u)
        return a
    }

    private val handler = object : IRtcEngineEventHandler() {
        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
            joined = true
            emit("joined", JSONObject().put("muted", muted).put("uids", uids()))
        }

        override fun onUserJoined(uid: Int, elapsed: Int) {
            remotes.add(uid)
            applyRemote(uid)
            emit("remote", JSONObject().put("uids", uids()))
        }

        override fun onUserOffline(uid: Int, reason: Int) {
            remotes.remove(uid)
            emit("remote", JSONObject().put("uids", uids()))
        }

        override fun onAudioVolumeIndication(speakers: Array<out AudioVolumeInfo>?, totalVolume: Int) {
            val talk = JSONArray()
            val list = mutableListOf<Int>()
            if (speakers != null) for (s in speakers) {
                val talking = if (s.uid == 0) (s.vad == 1 && s.volume > 8) else s.volume > 12
                if (talking) list.add(s.uid)
            }
            list.sort()
            for (u in list) talk.put(u)
            val key = list.joinToString(",")
            if (key != lastSpeaking) {
                lastSpeaking = key
                emit("speaking", JSONObject().put("uids", talk))
            }
        }

        override fun onConnectionStateChanged(state: Int, reason: Int) {
            val now = when (state) {
                Constants.CONNECTION_STATE_RECONNECTING -> "RECONNECTING"
                Constants.CONNECTION_STATE_CONNECTED -> "CONNECTED"
                Constants.CONNECTION_STATE_DISCONNECTED, Constants.CONNECTION_STATE_FAILED -> "DISCONNECTED"
                Constants.CONNECTION_STATE_CONNECTING -> "CONNECTING"
                else -> "UNKNOWN"
            }
            val why = when (reason) {
                Constants.CONNECTION_CHANGED_BANNED_BY_SERVER -> "UID_BANNED"
                Constants.CONNECTION_CHANGED_SAME_UID_LOGIN -> "UID_CONFLICT"
                Constants.CONNECTION_CHANGED_INVALID_TOKEN -> "INVALID_TOKEN"
                Constants.CONNECTION_CHANGED_TOKEN_EXPIRED -> "TOKEN_EXPIRE"
                Constants.CONNECTION_CHANGED_LEAVE_CHANNEL -> "LEAVE"
                Constants.CONNECTION_CHANGED_INTERRUPTED -> "NETWORK_ERROR"
                else -> "R$reason"
            }
            if (!joined && (state == Constants.CONNECTION_STATE_FAILED ||
                        reason == Constants.CONNECTION_CHANGED_INVALID_TOKEN || reason == Constants.CONNECTION_CHANGED_TOKEN_EXPIRED ||
                        reason == Constants.CONNECTION_CHANGED_INVALID_APP_ID || reason == Constants.CONNECTION_CHANGED_INVALID_CHANNEL_NAME)) {
                emit("error", JSONObject().put("stage", "join").put("code", if (why.startsWith("R")) "NETWORK_ERROR" else why))
                return
            }
            emit("state", JSONObject().put("now", now).put("reason", why))
        }

        override fun onTokenPrivilegeWillExpire(token: String?) { emit("will_expire") }

        override fun onRequestToken() { emit("expired") }

        override fun onLocalAudioStateChanged(state: Int, reason: Int) {
            if (state == Constants.LOCAL_AUDIO_STREAM_STATE_FAILED) {
                emit("mic_lost", JSONObject().put("code", "MIC_$reason"), false)
            }
        }

        override fun onError(err: Int) {
            Log.w("FraihaVoice", "agora error $err")
            if (!joined && (err == Constants.ERR_INVALID_TOKEN || err == Constants.ERR_TOKEN_EXPIRED || err == Constants.ERR_INVALID_APP_ID)) {
                emit("error", JSONObject().put("stage", "join").put("code", if (err == Constants.ERR_TOKEN_EXPIRED) "TOKEN_EXPIRE" else "INVALID_TOKEN"))
            } else {
                emit("warn", JSONObject().put("code", "E$err"))
            }
        }
    }

    private fun ensureEngine(appId: String): RtcEngine? {
        val act = activity ?: return null
        if (engine != null && appId == appIdUsed) return engine
        if (engine != null) { RtcEngine.destroy(); engine = null }
        val cfg = RtcEngineConfig()
        cfg.mContext = act.applicationContext
        cfg.mAppId = appId
        cfg.mEventHandler = handler
        cfg.mChannelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION
        cfg.mAudioScenario = Constants.AUDIO_SCENARIO_CHATROOM
        engine = RtcEngine.create(cfg)
        appIdUsed = appId
        engine?.apply {
            enableAudio()
            setDefaultAudioRoutetoSpeakerphone(true)
            enableAudioVolumeIndication(300, 3, true)
        }
        return engine
    }

    private fun applyRemote(uid: Int) {
        engine?.muteRemoteAudioStream(uid, speakerMuted || mutedUids.contains(uid))
    }

    @UsedByGodot
    fun join(s: Int, appId: String, channel: String, token: String, uid: Int, startMuted: Boolean, startSpeakerMuted: Boolean) {
        seq = s
        joined = false
        remotes.clear()
        lastSpeaking = ""
        muted = startMuted
        speakerMuted = startSpeakerMuted
        try {
            val e = ensureEngine(appId)
            if (e == null) { emit("error", JSONObject().put("stage", "sdk").put("code", "SDK_LOAD")); return }
            e.leaveChannel()
            e.muteLocalAudioStream(muted)
            e.muteAllRemoteAudioStreams(speakerMuted)
            val o = ChannelMediaOptions()
            o.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER
            o.channelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION
            o.publishMicrophoneTrack = true
            o.autoSubscribeAudio = true
            val r = e.joinChannel(token, channel, uid, o)
            if (r < 0) emit("error", JSONObject().put("stage", "join").put("code", "JOIN_$r"))
        } catch (t: Throwable) {
            Log.w("FraihaVoice", "join failed: ${t.javaClass.simpleName}")
            emit("error", JSONObject().put("stage", "sdk").put("code", "SDK_LOAD"))
        }
    }

    @UsedByGodot
    fun leave(s: Int, reason: String) {
        try { engine?.leaveChannel() } catch (_: Throwable) {}
        joined = false
        remotes.clear()
        mutedUids.clear()
        lastSpeaking = ""
        emit("left", JSONObject().put("reason", reason).put("seq", s), false)
    }

    @UsedByGodot
    fun setMuted(on: Boolean) {
        muted = on
        val r = engine?.muteLocalAudioStream(on) ?: 0
        if (r < 0) emit("error", JSONObject().put("stage", "mute").put("code", "MUTE_FAILED").put("soft", true), false)
        emit("muted", JSONObject().put("muted", muted), false)
    }

    @UsedByGodot
    fun setSpeakerMuted(on: Boolean) {
        speakerMuted = on
        engine?.muteAllRemoteAudioStreams(on)
        if (!on) for (u in remotes) applyRemote(u)
        val a = JSONArray(); for (u in mutedUids.sorted()) a.put(u)
        emit("speaker", JSONObject().put("muted", speakerMuted).put("uids", a), false)
    }

    @UsedByGodot
    fun setRemoteMuted(uid: Int, on: Boolean) {
        if (on) mutedUids.add(uid) else mutedUids.remove(uid)
        applyRemote(uid)
        val a = JSONArray(); for (u in mutedUids.sorted()) a.put(u)
        emit("speaker", JSONObject().put("muted", speakerMuted).put("uids", a), false)
    }

    @UsedByGodot
    fun renew(token: String) {
        val r = engine?.renewToken(token) ?: -1
        if (r < 0) emit("error", JSONObject().put("stage", "renew").put("code", "RENEW_$r").put("soft", true), false)
        else emit("renewed", JSONObject(), false)
    }

    override fun onMainDestroy() {
        try { engine?.leaveChannel(); RtcEngine.destroy() } catch (_: Throwable) {}
        engine = null
        super.onMainDestroy()
    }
}
