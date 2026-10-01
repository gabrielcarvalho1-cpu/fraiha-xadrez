extends SceneTree
## A cópia local da foto só vale para a URL de onde veio; URL nova do servidor = baixar de novo.
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _init():
    var Store = load("res://profile/avatar_store.gd")
    var st = Store.new()
    root.add_child(st)
    var key := "test_sync_user"
    st.clear_local(key)
    var url1 := "https://exemplo.supabase.co/storage/v1/object/public/avatars/u.webp?v=1"
    var url2 := "https://exemplo.supabase.co/storage/v1/object/public/avatars/u.webp?v=2"
    check(st.needs_fetch(key, url1), "sem cópia local: baixa")
    var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
    img.fill(Color.RED)
    st.save_local(key, img)
    check(st.needs_fetch(key, url1), "cópia local sem URL conhecida: baixa a do servidor")
    st.set_cached_url(key, url1)
    check(not st.needs_fetch(key, url1), "cópia local da mesma URL: não baixa")
    check(st.needs_fetch(key, url2), "servidor com URL nova (foto trocada em outro aparelho): baixa de novo")
    check(not st.needs_fetch(key, ""), "conta sem foto: nada a baixar")
    st.clear_local(key)
    check(st.cached_url(key) == "" and not st.has_local(key), "remover foto limpa cópia e URL")
    print("AVATAR_SYNC_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit(1 if failures else 0)
