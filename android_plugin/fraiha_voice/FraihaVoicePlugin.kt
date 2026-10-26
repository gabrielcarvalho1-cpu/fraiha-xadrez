// R183 · FRAIHA Voice no APP ANDROID: ponte Godot ↔ Agora Android SDK (só áudio).
// O GDScript (voice/agora_native_provider.gd) chama estes métodos; tudo o que acontece volta pelo sinal
// "voice_event" com um JSON igual ao do provedor da Web ({ev, seq, ...}), então o FraihaVoice não muda.
// Sem token no log. O token vem do servidor do jogo (voice_join), nunca é gerado aqui.
// Copiado para android/build/src pelo tools/android/montar_build_gradle.py (a pasta android/ é gerada).
package com.fraiha.voice

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import com.android.billingclient.api.AcknowledgePurchaseResponseListener
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
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

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("voice_event", String::class.java),
        SignalInfo("image_picked", String::class.java, String::class.java),
        SignalInfo("billing_event", String::class.java))

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

        // R185 · auditoria: estado REAL de publicação do microfone no logcat (0 ocioso, 1 não publicado, 2 publicando, 3 publicado)
        override fun onAudioPublishStateChanged(channel: String?, oldState: Int, newState: Int, elapseSinceLastState: Int) {
            Log.i("FraihaVoice", "publish $oldState->$newState muted=$muted")
        }

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
        Log.i("FraihaVoice", "setMuted on=$on joined=$joined r=$r")
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

    // ---------------------------------------------------------------- R185 · FOTO DE PERFIL no app
    // O FileDialog nativo do Godot devolvia um caminho que o app não consegue ler (armazenamento restrito do
    // Android 10+) e a foto nunca mudava. Aqui: abre a galeria do Android, lê pelo ContentResolver (permissão
    // temporária do próprio seletor, sem pedir acesso às fotos), decodifica qualquer formato que o celular
    // abre (JPG, PNG, WebP, HEIC), aplica a rotação da câmera, reduz para no máximo 1600 px e devolve JPEG em
    // base64 pelo sinal image_picked(tipo, dados): tipo = "ok" | "cancel" | "error".
    private val PICK_REQ = 7311

    private fun emitImage(kind: String, data: String) {
        runOnRenderThread { emitSignal("image_picked", kind, data) }
    }

    @UsedByGodot
    fun pickImage() {
        val act = activity
        if (act == null) { emitImage("error", "NO_ACTIVITY"); return }
        act.runOnUiThread {
            try {
                val i = if (Build.VERSION.SDK_INT >= 33) Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
                    else Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
                act.startActivityForResult(i, PICK_REQ)
            } catch (t: Throwable) {
                try {
                    act.startActivityForResult(Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE), PICK_REQ)
                } catch (t2: Throwable) {
                    Log.w("FraihaVoice", "pickImage: ${t2.javaClass.simpleName}")
                    emitImage("error", "NO_PICKER")
                }
            }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQ) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { emitImage("cancel", ""); return }
        val act = activity ?: run { emitImage("error", "NO_ACTIVITY"); return }
        Thread {
            try {
                val bmp = decode(act, uri)
                if (bmp == null) { emitImage("error", "DECODE"); return@Thread }
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
                Log.i("FraihaVoice", "image picked ${bmp.width}x${bmp.height} ${out.size()} bytes")
                emitImage("ok", Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP))
            } catch (t: Throwable) {
                Log.w("FraihaVoice", "image read failed: ${t.javaClass.simpleName}")
                emitImage("error", "READ")
            }
        }.start()
    }

    private fun decode(act: Activity, uri: Uri): Bitmap? {
        val maxSide = 1600
        if (Build.VERSION.SDK_INT >= 28) {
            val src = ImageDecoder.createSource(act.contentResolver, uri)
            return ImageDecoder.decodeBitmap(src) { dec, info, _ ->
                val w = info.size.width; val h = info.size.height
                val big = maxOf(w, h)
                if (big > maxSide) dec.setTargetSize(maxOf(1, w * maxSide / big), maxOf(1, h * maxSide / big))
                dec.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        act.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return act.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
    }

    // ---------------------------------------------------------------- R194 · COMPRAS PELO GOOGLE PLAY (só app da Play Store)
    // Play Billing 8. O GDScript (monetization/google_store.gd) chama estes métodos; tudo volta pelo sinal
    // "billing_event" com um JSON {ev, ...}. A compra NÃO é finalizada aqui: o servidor confere no Google e entrega;
    // só então billingFinish consome (Club, que pode ser comprado de novo) — o Fundador o servidor confirma lá.
    // Nada de cartão passa por aqui; só ids de produto e o token da compra.
    private var billing: BillingClient? = null
    private val productCache = HashMap<String, ProductDetails>()

    private fun emitBilling(o: JSONObject) {
        val s = o.toString()
        runOnRenderThread { emitSignal("billing_event", s) }
    }

    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> purchases?.forEach { emitPurchase(it) }
            BillingClient.BillingResponseCode.USER_CANCELED -> emitBilling(JSONObject().put("ev", "failed").put("cancelled", true).put("code", "CANCELED"))
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> { emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "OWNED")); billingPending() }
            else -> emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "E" + result.responseCode))
        }
    }

    private fun emitPurchase(p: Purchase) {
        val pid = if (p.products.isEmpty()) "" else p.products[0]
        when (p.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> emitBilling(JSONObject().put("ev", "purchased").put("product_id", pid)
                .put("purchase_token", p.purchaseToken).put("acknowledged", p.isAcknowledged))
            Purchase.PurchaseState.PENDING -> emitBilling(JSONObject().put("ev", "pending").put("product_id", pid))
            else -> {}
        }
    }

    private fun withBilling(then: (BillingClient) -> Unit) {
        val act = activity
        if (act == null) { emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "NO_ACTIVITY")); return }
        val b = billing ?: BillingClient.newBuilder(act.applicationContext)
            .setListener(purchasesListener)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build().also { billing = it }
        if (b.isReady) { then(b); return }
        b.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(r: BillingResult) {
                if (r.responseCode == BillingClient.BillingResponseCode.OK) then(b)
                else emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "SETUP_" + r.responseCode))
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    @UsedByGodot
    fun billingProducts(ids: Array<String>) {
        withBilling { b ->
            val list = ids.map { QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(BillingClient.ProductType.INAPP).build() }
            b.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(list).build()) { r, res ->
                val items = JSONArray()
                if (r.responseCode == BillingClient.BillingResponseCode.OK) {
                    for (pd in res.productDetailsList) {
                        productCache[pd.productId] = pd
                        items.put(JSONObject().put("id", pd.productId).put("price", pd.oneTimePurchaseOfferDetails?.formattedPrice ?: "").put("title", pd.name))
                    }
                }
                emitBilling(JSONObject().put("ev", "products").put("items", items))
            }
        }
    }

    // account = id da conta FRAIHA: o Google devolve como obfuscatedExternalAccountId e o servidor confere o dono
    @UsedByGodot
    fun billingBuy(productId: String, account: String) {
        withBilling { b ->
            val launch = { pd: ProductDetails ->
                val act = activity
                if (act == null) emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "NO_ACTIVITY"))
                else act.runOnUiThread {
                    val params = BillingFlowParams.newBuilder()
                        .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(pd).build()))
                        .setObfuscatedAccountId(account)
                        .build()
                    val r = b.launchBillingFlow(act, params)
                    if (r.responseCode != BillingClient.BillingResponseCode.OK && r.responseCode != BillingClient.BillingResponseCode.USER_CANCELED)
                        emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "E" + r.responseCode))
                }
            }
            val cached = productCache[productId]
            if (cached != null) { launch(cached); return@withBilling }
            val q = QueryProductDetailsParams.Product.newBuilder().setProductId(productId).setProductType(BillingClient.ProductType.INAPP).build()
            b.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(listOf(q)).build()) { r, res ->
                val pd = if (r.responseCode == BillingClient.BillingResponseCode.OK) res.productDetailsList.firstOrNull() else null
                if (pd == null) emitBilling(JSONObject().put("ev", "failed").put("cancelled", false).put("code", "PRODUCT").put("product_id", productId))
                else { productCache[productId] = pd; launch(pd) }
            }
        }
    }

    // o servidor confirmou: Club é consumido (pode comprar de novo); Fundador já foi confirmado pelo servidor
    @UsedByGodot
    fun billingFinish(token: String, consume: Boolean) {
        if (!consume) return
        withBilling { b ->
            b.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(token).build()) { r, _ ->
                emitBilling(JSONObject().put("ev", "consumed").put("ok", r.responseCode == BillingClient.BillingResponseCode.OK))
            }
        }
    }

    // reenvia as compras ainda não confirmadas (app fechado no meio, internet caiu): chamado ao abrir e ao entrar na conta
    @UsedByGodot
    fun billingPending() {
        withBilling { b ->
            b.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()) { r, list ->
                if (r.responseCode == BillingClient.BillingResponseCode.OK) for (p in list) if (!p.isAcknowledged) emitPurchase(p)
            }
        }
    }
}
