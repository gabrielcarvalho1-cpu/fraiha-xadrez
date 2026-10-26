// R188 · FRAIHA no APP DE IPHONE: ponte nativa Godot ↔ iOS (GDExtension em Objective-C++).
// É o "irmão" do plugin Android (android_plugin/fraiha_voice/FraihaVoicePlugin.kt): registra o MESMO singleton
// "FraihaVoice", com os MESMOS métodos e sinais, então o GDScript (voice/agora_native_provider.gd e
// profile/image_picker.gd) funciona igual nos dois celulares.
//  · Voz: Agora iOS SDK (só áudio). Tudo o que acontece volta pelo sinal "voice_event" com o JSON {ev, seq, ...}
//    igual ao do provedor da Web. O token vem do servidor do jogo (voice_join); nunca é gerado nem logado aqui.
//  · Microfone: requestMic(seq) pede a permissão do iPhone (a janela "Permitir microfone" do próprio iOS).
//  · R190 · Iniciar sessão com a Apple: signInWithApple(nonce_sha256) abre a janela do iPhone e devolve o id_token
//    pelo sinal apple_signin(tipo, dados): tipo = "ok" (dados = id_token) | "cancel" | "error" (dados = código).
//  · Foto de perfil: pickImage() abre a galeria do iPhone (PHPicker: não precisa pedir acesso às fotos), aplica a
//    rotação da câmera, reduz para no máximo 1600 px e devolve JPEG em base64 pelo sinal image_picked(tipo, dados):
//    tipo = "ok" | "cancel" | "error".
// Compilado só na montagem do iPhone (codemagic.yaml); a pasta tem .gdignore e não entra no jogo da Web/PC/Android.

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <StoreKit/StoreKit.h>
#import <AgoraRtcKit/AgoraRtcEngineKit.h>

#include <set>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

class FraihaIOS;

@interface FXBridge : NSObject <AgoraRtcEngineDelegate, PHPickerViewControllerDelegate,
		ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding,
		SKPaymentTransactionObserver, SKProductsRequestDelegate>
@property (nonatomic, assign) FraihaIOS *owner;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SKProduct *> *products;   // R192 · loja da Apple
@property (nonatomic, strong) SKProductsRequest *productsRequest;
@property (nonatomic, copy) NSString *pendingBuy;       // produto esperando os dados da Apple para comprar
@property (nonatomic, copy) NSString *pendingAccount;
@property (nonatomic, strong) ASAuthorizationController *appleController;
@end

static NSString *ns(const godot::String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()] ?: @"";
}

static godot::String gs(NSString *s) {
	return s == nil ? godot::String() : godot::String::utf8([s UTF8String]);
}

class FraihaIOS : public godot::Object {
	GDCLASS(FraihaIOS, godot::Object);

public:
	FXBridge *bridge = nil;
	AgoraRtcEngineKit *engine = nil;
	godot::String app_id_used;
	int64_t seq = 0;
	bool joined = false;
	bool muted = false;
	bool speaker_muted = false;
	std::set<int64_t> remotes;
	std::set<int64_t> muted_uids;
	godot::String last_speaking;

	FraihaIOS() {
		bridge = [FXBridge new];
		bridge.owner = this;
		bridge.products = [NSMutableDictionary new];
		// R192 · o observador entra JÁ na abertura do app: compras que ficaram pela metade (app fechado, internet caiu)
		// voltam para cá e são reenviadas ao servidor. O GDScript pede a lista de novo com iapPending().
		[[SKPaymentQueue defaultQueue] addTransactionObserver:bridge];
	}

	~FraihaIOS() {
		[[SKPaymentQueue defaultQueue] removeTransactionObserver:bridge];
		destroy_engine();
		bridge.owner = nullptr;
		bridge = nil;
	}

	// ------------------------------------------------------------------ eventos para o GDScript
	void emit_voice(NSString *ev, NSDictionary *extra = nil, bool with_seq = true) {
		NSMutableDictionary *d = extra ? [extra mutableCopy] : [NSMutableDictionary new];
		d[@"ev"] = ev;
		if (with_seq && d[@"seq"] == nil) d[@"seq"] = @(seq);
		NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
		if (json == nil) return;
		NSString *s = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
		godot::String gstr = gs(s);
		if ([NSThread isMainThread]) {
			emit_signal("voice_event", gstr);
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{ emit_signal("voice_event", gstr); });
		}
	}

	void emit_image(const godot::String &kind, const godot::String &data) {
		if ([NSThread isMainThread]) {
			emit_signal("image_picked", kind, data);
		} else {
			godot::String k = kind, v = data;
			dispatch_async(dispatch_get_main_queue(), ^{ emit_signal("image_picked", k, v); });
		}
	}

	// R192 · tudo da loja da Apple volta pelo sinal "iap_event" com um JSON {ev, ...}
	void emit_iap(NSDictionary *d) {
		NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
		if (json == nil) return;
		godot::String gstr = gs([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
		if ([NSThread isMainThread]) emit_signal("iap_event", gstr);
		else dispatch_async(dispatch_get_main_queue(), ^{ emit_signal("iap_event", gstr); });
	}

	void emit_transaction(SKPaymentTransaction *t) {
		BOOL restored = t.transactionState == SKPaymentTransactionStateRestored;
		NSString *orig = t.originalTransaction.transactionIdentifier ?: t.transactionIdentifier;
		emit_iap(@{@"ev": @"purchased", @"transaction_id": t.transactionIdentifier ?: @"", @"server_id": (restored ? orig : t.transactionIdentifier) ?: @"",
			@"product_id": t.payment.productIdentifier ?: @"", @"restored": @(restored)});
	}

	bool iapCanPay() { return [SKPaymentQueue canMakePayments]; }

	void iapProducts(const godot::PackedStringArray &ids) {
		NSMutableSet *set = [NSMutableSet new];
		for (int i = 0; i < ids.size(); i++) [set addObject:ns(ids[i])];
		bridge.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
		bridge.productsRequest.delegate = bridge;
		[bridge.productsRequest start];
	}

	// account = id da conta FRAIHA (UUID): a Apple devolve como appAccountToken e o servidor confere o dono
	void iapBuy(const godot::String &product, const godot::String &account) {
		if (![SKPaymentQueue canMakePayments]) { emit_iap(@{@"ev": @"failed", @"product_id": ns(product), @"code": @"NOT_ALLOWED", @"cancelled": @NO}); return; }
		bridge.pendingAccount = [ns(account) lowercaseString];
		SKProduct *p = bridge.products[ns(product)];
		if (p == nil) {   // ainda sem os dados do produto: pede e compra quando chegar
			bridge.pendingBuy = ns(product);
			godot::PackedStringArray one;
			one.push_back(product);
			iapProducts(one);
			return;
		}
		buy_now(p);
	}

	void buy_now(SKProduct *p) {
		SKMutablePayment *pay = [SKMutablePayment paymentWithProduct:p];
		pay.applicationUsername = bridge.pendingAccount;
		[[SKPaymentQueue defaultQueue] addPayment:pay];
	}

	// o servidor confirmou (ou recusou de vez): só então a compra sai da fila da Apple
	void iapFinish(const godot::String &transaction_id) {
		NSString *tid = ns(transaction_id);
		for (SKPaymentTransaction *t in [SKPaymentQueue defaultQueue].transactions) {
			if ([t.transactionIdentifier isEqualToString:tid] && t.transactionState != SKPaymentTransactionStatePurchasing)
				[[SKPaymentQueue defaultQueue] finishTransaction:t];
		}
	}

	void iapRestore() { [[SKPaymentQueue defaultQueue] restoreCompletedTransactions]; }

	// reenvia o que ainda está na fila (compras não finalizadas): chamado ao abrir e ao entrar na conta
	void iapPending() {
		for (SKPaymentTransaction *t in [SKPaymentQueue defaultQueue].transactions) {
			if (t.transactionState == SKPaymentTransactionStatePurchased || t.transactionState == SKPaymentTransactionStateRestored) emit_transaction(t);
		}
	}

	NSArray *sorted(const std::set<int64_t> &s) {
		NSMutableArray *a = [NSMutableArray new];
		for (int64_t u : s) [a addObject:@(u)];   // std::set já é ordenado
		return a;
	}

	NSArray *uids() { return sorted(remotes); }

	// ------------------------------------------------------------------ voz (Agora)
	void destroy_engine() {
		if (engine != nil) {
			[engine leaveChannel:nil];
			[AgoraRtcEngineKit destroy];
			engine = nil;
		}
	}

	AgoraRtcEngineKit *ensure_engine(const godot::String &app_id) {
		if (engine != nil && app_id == app_id_used) return engine;
		destroy_engine();
		AgoraRtcEngineConfig *cfg = [AgoraRtcEngineConfig new];
		cfg.appId = ns(app_id);
		cfg.channelProfile = AgoraChannelProfileCommunication;
		cfg.audioScenario = AgoraAudioScenarioChatRoom;
		engine = [AgoraRtcEngineKit sharedEngineWithConfig:cfg delegate:bridge];
		app_id_used = app_id;
		if (engine != nil) {
			[engine enableAudio];
			[engine setDefaultAudioRouteToSpeakerphone:YES];
			[engine enableAudioVolumeIndication:300 smooth:3 reportVad:YES];
		}
		return engine;
	}

	void apply_remote(int64_t uid) {
		if (engine == nil) return;
		[engine muteRemoteAudioStream:(NSUInteger)uid mute:(speaker_muted || muted_uids.count(uid) > 0)];
	}

	void requestMic(int64_t s) {
		AVAudioSession *a = [AVAudioSession sharedInstance];
		AVAudioSessionRecordPermission p = [a recordPermission];
		if (p == AVAudioSessionRecordPermissionGranted) {
			emit_voice(@"mic_ready", @{@"seq": @(s)}, false);
		} else if (p == AVAudioSessionRecordPermissionDenied) {
			emit_voice(@"error", @{@"seq": @(s), @"stage": @"mic", @"code": @"PERMISSION_DENIED"}, false);
		} else {
			[a requestRecordPermission:^(BOOL granted) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (granted) emit_voice(@"mic_ready", @{@"seq": @(s)}, false);
					else emit_voice(@"error", @{@"seq": @(s), @"stage": @"mic", @"code": @"PERMISSION_DENIED"}, false);
				});
			}];
		}
	}

	godot::String micPermission() {
		switch ([[AVAudioSession sharedInstance] recordPermission]) {
			case AVAudioSessionRecordPermissionGranted: return "granted";
			case AVAudioSessionRecordPermissionDenied: return "denied";
			default: return "undetermined";
		}
	}

	void join(int64_t s, const godot::String &app_id, const godot::String &channel, const godot::String &token,
			int64_t uid, bool start_muted, bool start_speaker_muted) {
		seq = s;
		joined = false;
		remotes.clear();
		last_speaking = "";
		muted = start_muted;
		speaker_muted = start_speaker_muted;
		AgoraRtcEngineKit *e = ensure_engine(app_id);
		if (e == nil) {
			emit_voice(@"error", @{@"stage": @"sdk", @"code": @"SDK_LOAD"});
			return;
		}
		[e leaveChannel:nil];
		[e muteLocalAudioStream:muted];
		[e muteAllRemoteAudioStreams:speaker_muted];
		AgoraRtcChannelMediaOptions *o = [AgoraRtcChannelMediaOptions new];
		o.clientRoleType = AgoraClientRoleBroadcaster;
		o.channelProfile = AgoraChannelProfileCommunication;
		o.publishMicrophoneTrack = YES;
		o.autoSubscribeAudio = YES;
		int r = [e joinChannelByToken:ns(token) channelId:ns(channel) uid:(NSUInteger)uid mediaOptions:o joinSuccess:nil];
		if (r < 0) emit_voice(@"error", @{@"stage": @"join", @"code": [NSString stringWithFormat:@"JOIN_%d", r]});
	}

	void leave(int64_t s, const godot::String &reason) {
		if (engine != nil) [engine leaveChannel:nil];
		joined = false;
		remotes.clear();
		muted_uids.clear();
		last_speaking = "";
		emit_voice(@"left", @{@"reason": ns(reason), @"seq": @(s)}, false);
	}

	void setMuted(bool on) {
		muted = on;
		int r = engine != nil ? [engine muteLocalAudioStream:on] : 0;
		if (r < 0) emit_voice(@"error", @{@"stage": @"mute", @"code": @"MUTE_FAILED", @"soft": @YES}, false);
		emit_voice(@"muted", @{@"muted": @(muted)}, false);
	}

	void setSpeakerMuted(bool on) {
		speaker_muted = on;
		if (engine != nil) [engine muteAllRemoteAudioStreams:on];
		if (!on) for (int64_t u : remotes) apply_remote(u);
		emit_voice(@"speaker", @{@"muted": @(speaker_muted), @"uids": sorted(muted_uids)}, false);
	}

	void setRemoteMuted(int64_t uid, bool on) {
		if (on) muted_uids.insert(uid); else muted_uids.erase(uid);
		apply_remote(uid);
		emit_voice(@"speaker", @{@"muted": @(speaker_muted), @"uids": sorted(muted_uids)}, false);
	}

	void renew(const godot::String &token) {
		int r = engine != nil ? [engine renewToken:ns(token)] : -1;
		if (r < 0) emit_voice(@"error", @{@"stage": @"renew", @"code": [NSString stringWithFormat:@"RENEW_%d", r], @"soft": @YES}, false);
		else emit_voice(@"renewed", nil, false);
	}

	void emit_apple(const godot::String &kind, const godot::String &data) {
		godot::String k = kind, v = data;
		if ([NSThread isMainThread]) emit_signal("apple_signin", k, v);
		else dispatch_async(dispatch_get_main_queue(), ^{ emit_signal("apple_signin", k, v); });
	}

	// ------------------------------------------------------------------ R190 · Iniciar sessão com a Apple
	void signInWithApple(const godot::String &nonce_sha256) {
		ASAuthorizationAppleIDProvider *p = [ASAuthorizationAppleIDProvider new];
		ASAuthorizationAppleIDRequest *req = [p createRequest];
		req.requestedScopes = @[ASAuthorizationScopeEmail];
		req.nonce = ns(nonce_sha256);
		ASAuthorizationController *c = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[req]];
		c.delegate = bridge;
		c.presentationContextProvider = bridge;
		bridge.appleController = c;   // segura o controlador até a resposta
		[c performRequests];
	}

	// ------------------------------------------------------------------ foto de perfil (galeria)
	static UIWindow *key_window() {
		UIWindow *win = nil;
		for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
			if (![sc isKindOfClass:[UIWindowScene class]]) continue;
			for (UIWindow *w in ((UIWindowScene *)sc).windows) {
				if (w.isKeyWindow) return w;
				if (win == nil) win = w;
			}
		}
		return win;
	}

	static UIViewController *top_controller() {
		UIWindow *win = nil;
		for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
			if (![sc isKindOfClass:[UIWindowScene class]]) continue;
			for (UIWindow *w in ((UIWindowScene *)sc).windows) {
				if (w.isKeyWindow) { win = w; break; }
				if (win == nil) win = w;
			}
		}
		UIViewController *vc = win.rootViewController;
		while (vc.presentedViewController != nil) vc = vc.presentedViewController;
		return vc;
	}

	void pickImage() {
		UIViewController *vc = top_controller();
		if (vc == nil) { emit_image("error", "NO_ACTIVITY"); return; }
		PHPickerConfiguration *c = [[PHPickerConfiguration alloc] init];
		c.filter = [PHPickerFilter imagesFilter];
		c.selectionLimit = 1;
		PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c];
		p.delegate = bridge;
		[vc presentViewController:p animated:YES completion:nil];
	}

protected:
	static void _bind_methods() {
		using godot::ClassDB;
		using godot::D_METHOD;
		ClassDB::bind_method(D_METHOD("requestMic", "seq"), &FraihaIOS::requestMic);
		ClassDB::bind_method(D_METHOD("micPermission"), &FraihaIOS::micPermission);
		ClassDB::bind_method(D_METHOD("join", "seq", "app_id", "channel", "token", "uid", "muted", "speaker_muted"), &FraihaIOS::join);
		ClassDB::bind_method(D_METHOD("leave", "seq", "reason"), &FraihaIOS::leave);
		ClassDB::bind_method(D_METHOD("setMuted", "on"), &FraihaIOS::setMuted);
		ClassDB::bind_method(D_METHOD("setSpeakerMuted", "on"), &FraihaIOS::setSpeakerMuted);
		ClassDB::bind_method(D_METHOD("setRemoteMuted", "uid", "on"), &FraihaIOS::setRemoteMuted);
		ClassDB::bind_method(D_METHOD("renew", "token"), &FraihaIOS::renew);
		ClassDB::bind_method(D_METHOD("pickImage"), &FraihaIOS::pickImage);
		ClassDB::bind_method(D_METHOD("signInWithApple", "nonce_sha256"), &FraihaIOS::signInWithApple);
		ClassDB::bind_method(D_METHOD("iapCanPay"), &FraihaIOS::iapCanPay);
		ClassDB::bind_method(D_METHOD("iapProducts", "ids"), &FraihaIOS::iapProducts);
		ClassDB::bind_method(D_METHOD("iapBuy", "product", "account"), &FraihaIOS::iapBuy);
		ClassDB::bind_method(D_METHOD("iapFinish", "transaction_id"), &FraihaIOS::iapFinish);
		ClassDB::bind_method(D_METHOD("iapRestore"), &FraihaIOS::iapRestore);
		ClassDB::bind_method(D_METHOD("iapPending"), &FraihaIOS::iapPending);
		ADD_SIGNAL(godot::MethodInfo("iap_event", godot::PropertyInfo(godot::Variant::STRING, "json")));
		ADD_SIGNAL(godot::MethodInfo("voice_event", godot::PropertyInfo(godot::Variant::STRING, "json")));
		ADD_SIGNAL(godot::MethodInfo("apple_signin", godot::PropertyInfo(godot::Variant::STRING, "kind"), godot::PropertyInfo(godot::Variant::STRING, "data")));
		ADD_SIGNAL(godot::MethodInfo("image_picked", godot::PropertyInfo(godot::Variant::STRING, "kind"), godot::PropertyInfo(godot::Variant::STRING, "data")));
	}
};

// ====================================================================== delegados do iOS
@implementation FXBridge

// ---------------------------------------------------------------- Agora
- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinChannel:(NSString *)channel withUid:(NSUInteger)uid elapsed:(NSInteger)elapsed {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->joined = true;
	o->emit_voice(@"joined", @{@"muted": @(o->muted), @"uids": o->uids()});
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinedOfUid:(NSUInteger)uid elapsed:(NSInteger)elapsed {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->remotes.insert((int64_t)uid);
	o->apply_remote((int64_t)uid);
	o->emit_voice(@"remote", @{@"uids": o->uids()});
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOfflineOfUid:(NSUInteger)uid reason:(AgoraUserOfflineReason)reason {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->remotes.erase((int64_t)uid);
	o->emit_voice(@"remote", @{@"uids": o->uids()});
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine reportAudioVolumeIndicationOfSpeakers:(NSArray<AgoraRtcAudioVolumeInfo *> *)speakers totalVolume:(NSInteger)totalVolume {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	std::set<int64_t> talk;
	for (AgoraRtcAudioVolumeInfo *s in speakers) {
		bool talking = s.uid == 0 ? (s.vad == 1 && s.volume > 8) : s.volume > 12;
		if (talking) talk.insert((int64_t)s.uid);
	}
	godot::String key;
	for (int64_t u : talk) key += godot::String::num_int64(u) + ",";
	if (key != o->last_speaking) {
		o->last_speaking = key;
		o->emit_voice(@"speaking", @{@"uids": o->sorted(talk)});
	}
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine connectionChangedToState:(AgoraConnectionState)state reason:(AgoraConnectionChangedReason)reason {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	NSString *now = @"UNKNOWN";
	switch (state) {
		case AgoraConnectionStateReconnecting: now = @"RECONNECTING"; break;
		case AgoraConnectionStateConnected: now = @"CONNECTED"; break;
		case AgoraConnectionStateDisconnected:
		case AgoraConnectionStateFailed: now = @"DISCONNECTED"; break;
		case AgoraConnectionStateConnecting: now = @"CONNECTING"; break;
		default: break;
	}
	NSString *why = nil;
	switch (reason) {
		case AgoraConnectionChangedReasonBannedByServer: why = @"UID_BANNED"; break;
		case AgoraConnectionChangedSameUidLogin: why = @"UID_CONFLICT"; break;
		case AgoraConnectionChangedReasonInvalidToken: why = @"INVALID_TOKEN"; break;
		case AgoraConnectionChangedReasonTokenExpired: why = @"TOKEN_EXPIRE"; break;
		case AgoraConnectionChangedReasonLeaveChannel: why = @"LEAVE"; break;
		case AgoraConnectionChangedReasonInterrupted: why = @"NETWORK_ERROR"; break;
		default: why = [NSString stringWithFormat:@"R%ld", (long)reason]; break;
	}
	if (!o->joined && (state == AgoraConnectionStateFailed ||
			reason == AgoraConnectionChangedReasonInvalidToken || reason == AgoraConnectionChangedReasonTokenExpired ||
			reason == AgoraConnectionChangedReasonInvalidAppId || reason == AgoraConnectionChangedReasonInvalidChannelName)) {
		o->emit_voice(@"error", @{@"stage": @"join", @"code": [why hasPrefix:@"R"] ? @"NETWORK_ERROR" : why});
		return;
	}
	o->emit_voice(@"state", @{@"now": now, @"reason": why});
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine tokenPrivilegeWillExpire:(NSString *)token {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->emit_voice(@"will_expire");
}

- (void)rtcEngineRequestToken:(AgoraRtcEngineKit *)engine {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->emit_voice(@"expired");
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine localAudioStateChanged:(AgoraAudioLocalState)state reason:(AgoraAudioLocalReason)reason {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	if (state == AgoraAudioLocalStateFailed) {
		o->emit_voice(@"mic_lost", @{@"code": [NSString stringWithFormat:@"MIC_%ld", (long)reason]}, false);
	}
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOccurError:(AgoraErrorCode)err {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	if (!o->joined && (err == AgoraErrorCodeInvalidToken || err == AgoraErrorCodeTokenExpired || err == AgoraErrorCodeInvalidAppId)) {
		o->emit_voice(@"error", @{@"stage": @"join", @"code": err == AgoraErrorCodeTokenExpired ? @"TOKEN_EXPIRE" : @"INVALID_TOKEN"});
	} else {
		o->emit_voice(@"warn", @{@"code": [NSString stringWithFormat:@"E%ld", (long)err]});
	}
}

// ---------------------------------------------------------------- R190 · Apple
- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
	self.appleController = nil;
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	if (![authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) { o->emit_apple("error", "CREDENTIAL"); return; }
	ASAuthorizationAppleIDCredential *cred = (ASAuthorizationAppleIDCredential *)authorization.credential;
	NSString *tok = cred.identityToken ? [[NSString alloc] initWithData:cred.identityToken encoding:NSUTF8StringEncoding] : nil;
	if (tok.length == 0) { o->emit_apple("error", "NO_TOKEN"); return; }
	o->emit_apple("ok", gs(tok));
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
	self.appleController = nil;
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	if (error.code == ASAuthorizationErrorCanceled) o->emit_apple("cancel", "");
	else o->emit_apple("error", gs([NSString stringWithFormat:@"E%ld", (long)error.code]));
}

// ---------------------------------------------------------------- R192 · loja da Apple (StoreKit)
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	NSMutableArray *items = [NSMutableArray new];
	for (SKProduct *p in response.products) {
		self.products[p.productIdentifier] = p;
		NSNumberFormatter *f = [NSNumberFormatter new];
		f.numberStyle = NSNumberFormatterCurrencyStyle;
		f.locale = p.priceLocale;
		[items addObject:@{@"id": p.productIdentifier, @"price": [f stringFromNumber:p.price] ?: @"", @"title": p.localizedTitle ?: @""}];
	}
	o->emit_iap(@{@"ev": @"products", @"items": items, @"invalid": response.invalidProductIdentifiers ?: @[]});
	if (self.pendingBuy != nil) {
		SKProduct *p = self.products[self.pendingBuy];
		NSString *want = self.pendingBuy;
		self.pendingBuy = nil;
		if (p != nil) o->buy_now(p);
		else o->emit_iap(@{@"ev": @"failed", @"product_id": want, @"code": @"PRODUCT", @"cancelled": @NO});
	}
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	NSString *want = self.pendingBuy ?: @"";
	self.pendingBuy = nil;
	o->emit_iap(@{@"ev": @"failed", @"product_id": want, @"code": [NSString stringWithFormat:@"STORE_%ld", (long)error.code], @"cancelled": @NO});
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	for (SKPaymentTransaction *t in transactions) {
		switch (t.transactionState) {
			case SKPaymentTransactionStatePurchased:
			case SKPaymentTransactionStateRestored:
				o->emit_transaction(t);   // NÃO finaliza aqui: só depois que o servidor confirmar (iapFinish)
				break;
			case SKPaymentTransactionStateFailed: {
				BOOL cancelled = t.error != nil && t.error.code == SKErrorPaymentCancelled;
				o->emit_iap(@{@"ev": @"failed", @"product_id": t.payment.productIdentifier ?: @"",
					@"code": [NSString stringWithFormat:@"E%ld", (long)(t.error ? t.error.code : 0)], @"cancelled": @(cancelled)});
				[queue finishTransaction:t];
				break;
			}
			case SKPaymentTransactionStateDeferred:   // "Pedir para comprar": esperando o responsável aprovar
				o->emit_iap(@{@"ev": @"deferred", @"product_id": t.payment.productIdentifier ?: @""});
				break;
			default: break;
		}
	}
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->emit_iap(@{@"ev": @"restore_done"});
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	o->emit_iap(@{@"ev": @"restore_failed", @"code": [NSString stringWithFormat:@"E%ld", (long)error.code]});
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	return FraihaIOS::key_window();
}

// ---------------------------------------------------------------- galeria
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	FraihaIOS *o = self.owner; if (o == nullptr) return;
	NSItemProvider *ip = results.firstObject.itemProvider;
	if (ip == nil) { o->emit_image("cancel", ""); return; }
	if (![ip canLoadObjectOfClass:[UIImage class]]) { o->emit_image("error", "DECODE"); return; }
	[ip loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *error) {
		FraihaIOS *ow = self.owner; if (ow == nullptr) return;
		UIImage *img = [obj isKindOfClass:[UIImage class]] ? (UIImage *)obj : nil;
		if (img == nil) { ow->emit_image("error", "READ"); return; }
		CGSize sz = img.size;
		CGFloat big = fmax(sz.width, sz.height);
		CGFloat k = big > 1600 ? 1600.0 / big : 1.0;
		CGSize dst = CGSizeMake(fmax(1.0, floor(sz.width * k)), fmax(1.0, floor(sz.height * k)));
		UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
		fmt.scale = 1;
		fmt.opaque = YES;
		UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:dst format:fmt];
		// desenhar o UIImage já aplica a rotação da câmera (EXIF) e converte HEIC/PNG/WebP
		NSData *jpg = [r JPEGDataWithCompressionQuality:0.9 actions:^(UIGraphicsImageRendererContext *ctx) {
			[img drawInRect:CGRectMake(0, 0, dst.width, dst.height)];
		}];
		if (jpg.length == 0) { ow->emit_image("error", "DECODE"); return; }
		ow->emit_image("ok", gs([jpg base64EncodedStringWithOptions:0]));
	}];
}

@end

// ====================================================================== registro no Godot
static FraihaIOS *g_fraiha = nullptr;

static void fraiha_initialize(godot::ModuleInitializationLevel level) {
	if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
	GDREGISTER_CLASS(FraihaIOS);
	g_fraiha = memnew(FraihaIOS);
	godot::Engine::get_singleton()->register_singleton("FraihaVoice", g_fraiha);
}

static void fraiha_uninitialize(godot::ModuleInitializationLevel level) {
	if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
	if (g_fraiha != nullptr) {
		godot::Engine::get_singleton()->unregister_singleton("FraihaVoice");
		memdelete(g_fraiha);
		g_fraiha = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT fraiha_ios_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(fraiha_initialize);
	init_obj.register_terminator(fraiha_uninitialize);
	init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
