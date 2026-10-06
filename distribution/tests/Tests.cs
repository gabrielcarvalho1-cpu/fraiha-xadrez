using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32.SafeHandles;

namespace Fraiha.Distribution {
    public sealed class MockServer:IDisposable {
        readonly TcpListener listener;readonly Thread thread;volatile bool stopping;
        public byte[] Payload;public string ManifestJson;public string Mode="ok";public int Port;
        public MockServer(int port=0) {listener=new TcpListener(IPAddress.Loopback,port);listener.Start();Port=((IPEndPoint)listener.LocalEndpoint).Port;thread=new Thread(Serve);thread.IsBackground=true;thread.Start();}
        public string Url {get{return "http://127.0.0.1:"+Port;}}
        void Serve() {while(!stopping) {try{var client=listener.AcceptTcpClient();ThreadPool.QueueUserWorkItem(delegate {Handle(client);});}catch(SocketException){if(!stopping)throw;}}}
        void Handle(TcpClient client) {using(client) {try{using(var stream=client.GetStream()) {
            stream.ReadTimeout=1000;var header=new StringBuilder();int b;while((b=stream.ReadByte())>=0) {header.Append((char)b);if(header.ToString().EndsWith("\r\n\r\n",StringComparison.Ordinal))break;if(header.Length>8192)return;}
            bool manifest=header.ToString().Contains(" /manifest.json ");string mode=Mode;byte[] body=manifest?Encoding.UTF8.GetBytes(ManifestJson??"{}"):Payload;
            if(mode=="timeout")Thread.Sleep(600);
            string response=mode=="redirect"?"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:"+Port+"/package.zip\r\nContent-Length: 0\r\nConnection: close\r\n\r\n": "HTTP/1.1 200 OK\r\nContent-Length: "+(mode=="oversize"?Manifest.MaxPackage+1:body.Length)+"\r\nConnection: close\r\n\r\n";
            byte[] bytes=Encoding.ASCII.GetBytes(response);stream.Write(bytes,0,bytes.Length);if(mode=="redirect" || mode=="oversize")return;
            if(mode=="corrupt") {body=(byte[])body.Clone();body[body.Length/2]^=0xFF;}
            stream.Write(body,0,mode=="partial"?body.Length/2:body.Length);
        }}catch(IOException){}catch(ObjectDisposedException){}}}
        public void Dispose(){stopping=true;listener.Stop();thread.Join(1000);}
    }
    public static class Tests {
        static string root;static int passed,failed;static readonly List<string> lines=new List<string>();
        static void Check(bool ok,string message) {if(!ok)throw new Exception(message);}
        static void Reject(Action a) {bool rejected=false;try{a();}catch(InvalidDataException){rejected=true;}catch(IOException){rejected=true;}catch(WebException){rejected=true;}catch(InvalidOperationException){rejected=true;}catch(TimeoutException){rejected=true;}Check(rejected,"Expected operation rejection");}
        static void Case(string name,Action action) {try{action();passed++;lines.Add("PASS "+name);Console.WriteLine("PASS "+name);}catch(Exception e){failed++;lines.Add("FAIL "+name+": "+e);Console.WriteLine("FAIL "+name+": "+e);}}
        static string Dir(string name) {string p=Path.Combine(root,name+"-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(p);return p;}
        static Release R(long build) {return new Release{Version="0.0.0",Build=build,Channel="DEV",Platform="windows_site",DevOnly=true,Protocol=0,Rules=0};}
        static Manifest Offer(MockServer server,long build) {
            string source=Dir("export");File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"FRAIHA.exe"),Path.Combine(source,"FRAIHA.exe"));File.WriteAllText(Path.Combine(source,"FRAIHA.pck"),"NOT A GODOT PCK; LOCAL DEV STUB FIXTURE",new UTF8Encoding(false));
            string version=Path.Combine(Dir("version"),"version.json");File.WriteAllText(version,Json.Write(R(build).Data()));
            string output=Dir("package");var m=PackageTool.Package(version,source,output,server.Url+"/package.zip","DEV test stub only; not Godot");
            server.Payload=File.ReadAllBytes(Path.Combine(output,"fraiha-"+m.Release.Id+".zip"));server.ManifestJson=Json.Write(m.Data());return m;
        }
        static void ClearTemp(Updater u) {string temp=Path.Combine(u.Root,"temp");Check(!Directory.Exists(temp) || Directory.GetFileSystemEntries(temp).Length==0,"Partial staging must be removed");}
        static Manifest Changed(Manifest m,string key,object value) {var d=m.Data();d[key]=value;return Manifest.Read(Json.Write(d));}
        [STAThread]public static int Main() {
            Paths.InitializeRuntime();
            root=DirUnderBase();
            Case("reviewed pins approve ONLY the offline DEV online.cfg (R46 audit)",delegate {
                string dir=Dir("pins-offline");string ok=Path.Combine(dir,"ok.txt"),bad=Path.Combine(dir,"bad.txt");
                byte[] offline=new UTF8Encoding(false).GetBytes("[online]\nserver_url=\"\"\n"),online=new UTF8Encoding(false).GetBytes("[online]\nserver_url=\"wss://example.invalid\"\n");
                Check(HashBytes(offline)==ReviewedPins.OfflineCfgSha,"offline profile hash matches contract");
                File.WriteAllText(ok,"# t\nexe "+new string('a',64)+"\npck "+new string('b',64)+"\ncfg "+HashBytes(offline)+"\n",new UTF8Encoding(false));
                Check(ReviewedPins.Load(ok).Count==3,"offline cfg pin accepted");
                File.WriteAllText(bad,"exe "+new string('a',64)+"\npck "+new string('b',64)+"\ncfg "+HashBytes(online)+"\n",new UTF8Encoding(false));
                Reject(delegate{ReviewedPins.Load(bad);});
            });
            Case("site updater refuses Steam installs (Steam updates its own copy)",delegate {Reject(delegate{new Updater(Path.Combine(Dir("steam"),"steamapps","common","FRAIHA"));});Reject(delegate{new Updater(Path.Combine(Dir("steam2"),"SteamApps","common","FRAIHA"));});});
            Case("central DEV version read/schema",delegate {var r=Release.Read(Json.ReadFile(Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../../version.json"))));Check(r.Id=="0.0.0-1" && r.DevOnly,"Explicit unassigned DEV version");});
            Case("version ordering same/higher/lower/channel/platform",delegate {
                Release.RequireUpgrade(R(1),R(2));Reject(delegate{Release.RequireUpgrade(R(2),R(2));});Reject(delegate{Release.RequireUpgrade(R(2),R(1));});
                var a=R(3);a.Version="0.0.1";Release.RequireUpgrade(R(2),a);a.Version="0.0.0";var old=R(2);old.Version="0.1.0";Reject(delegate{Release.RequireUpgrade(old,a);});
                a.Channel="BETA";Reject(delegate{Release.RequireUpgrade(R(1),a);});a.Channel="DEV";a.Platform="windows_steam";Reject(delegate{Release.RequireUpgrade(R(1),a);});
            });
            Case("compatibility maintenance/protocol/rules/build cross-platform",delegate {
                foreach(string platform in Release.Platforms) {var r=R(1);r.Platform=platform;Check(CompatibilityContract.Evaluate(r,0,0,1,false)==Compatibility.COMPATIBLE,"Platform must not partition");Check(CompatibilityContract.Evaluate(r,0,0,2,false)==Compatibility.UPDATE_REQUIRED,"Build minimum");Check(CompatibilityContract.Evaluate(r,1,0,1,false)==Compatibility.INCOMPATIBLE_PROTOCOL,"Protocol mismatch");Check(CompatibilityContract.Evaluate(r,0,1,1,false)==Compatibility.INCOMPATIBLE_PROTOCOL,"Rules mismatch");Check(CompatibilityContract.Evaluate(r,1,1,2,true)==Compatibility.MAINTENANCE,"Maintenance precedence");}
            });
            Case("strict JSON duplicate/escaped aliases/types/unknowns/trailing",delegate {
                string json=Json.Write(R(1).Data());foreach(string invalid in new[]{json.Replace("\"build_number\":1","\"build_number\":1,\"build_number\":2"),json.Replace("\"build_number\":1","\"build_number\":1,\"build_\\u006eumber\":2"),json.Replace("\"build_number\":1","\"build_number\":\"1\""),json.Replace("\"build_number\":1","\"build_number\":01"),json.Replace("\"build_number\":1","\"build_number\":1.0"),json.Replace("\"build_number\":1","\"build_number\":-1"),json.Replace("\"build_number\":1","\"build_number\":9999999999999999999999"),json.Replace("\"build_number\":1","\"build_number\":null"),json.Replace("\"build_number\":1","\"build_number\":{}"),json.Replace("\"build_number\":1","\"build_number\":1,\"command\":\"calc.exe\""),json+"x"})Reject(delegate{Release.Read(invalid);});
                foreach(string v in new[]{"../x","C:\\x","01.0.0","1.2","1.2.3-beta","1.2.3/4"}){var d=R(1).Data();d["game_version"]=v;Reject(delegate{Release.Read(Json.Write(d));});}
                foreach(string ch in new[]{"dev","INTERNAL","STABLE/../DEV",""}){var d=R(1).Data();d["release_channel"]=ch;Reject(delegate{Release.Read(Json.Write(d));});}
                var prod=R(1).Data();prod["release_channel"]="STABLE";Reject(delegate{Release.Read(Json.Write(prod));});
            });
            Case("URL HTTPS/literal DEV loopback and unsafe forms",delegate {
                Manifest.SafeUrl("https://updates.example.com/game.zip","STABLE");Manifest.SafeUrl("http://127.0.0.1:8765/game.zip","DEV");Manifest.SafeUrl("http://[::1]:8765/game.zip","DEV");
                foreach(string u in new[]{"http://example.com/game.zip","http://localhost/game.zip","http://127.1/game.zip","file:///C:/evil","ftp://example.com/a","https://user:pass@example.com/a","https://example.com/a#x","https://example.com/a?x=1","https://example.com/a/../evil","https://example.com/%2e%2e/a","https://example.com/%252e/a","https://example.com/a\\evil","//example.com/a","https://example.com/%2f/a"})Reject(delegate{Manifest.SafeUrl(u,"DEV");});
                Reject(delegate{Manifest.SafeUrl("http://127.0.0.1/a","BETA");});
            });
            using(var server=new MockServer()) {
                Case("v2 complete fixed payload hashes limits opt-in and malicious extras",delegate {
                    string source=Dir("v2-export");
                    File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"FRAIHA.exe"),Path.Combine(source,"FRAIHA.exe"));File.WriteAllText(Path.Combine(source,"FRAIHA.pck"),"V2 MOCK PCK");File.WriteAllText(Path.Combine(source,"online.cfg"),"[online]\nserver_url=\"\"\n");File.WriteAllText(Path.Combine(source,"LEIA-ME.txt"),"MOCK ONLY");
                    string version=Path.Combine(Dir("v2-version"),"version.json");File.WriteAllText(version,Json.Write(R(1).Data()));
                    string output=Dir("v2-feed");var m=PackageTool.Package(version,source,output,server.Url+"/package.zip","v2 mock");Check(m.CompleteExport && m.Files.Length==4,"v2 fixed file count");server.Payload=File.ReadAllBytes(Path.Combine(output,"fraiha-"+m.Release.Id+".zip"));server.ManifestJson=Json.Write(m.Data());
                    var u=new Updater(Dir("v2-install"));u.Install(m,null);Check(u.Installed().CompleteExport,"Four files verified");Reject(u.Play);u.RealOffline=true;Reject(u.Play); // Unreviewed mock PCK cannot masquerade as a real offline export.
                    foreach(string name in new[]{"online.cfg","LEIA-ME.txt"}){string f=Path.Combine(u.Root,"versions",m.Release.Id,name),oldText=File.ReadAllText(f);File.AppendAllText(f,"tamper");Reject(delegate{u.Installed();});File.WriteAllText(f,oldText,new UTF8Encoding(false));}
                    foreach(string key in new[]{"cfg_size","cfg_sha256","readme_size","readme_sha256"}){var d=m.Data();d.Remove(key);Reject(delegate{Manifest.Read(Json.Write(d));});}
                    foreach(var pair in new[]{new KeyValuePair<string,object>("cfg_size",0L),new KeyValuePair<string,object>("cfg_size",32769L),new KeyValuePair<string,object>("readme_size",1048577L),new KeyValuePair<string,object>("cfg_sha256","BAD"),new KeyValuePair<string,object>("readme_sha256","BAD")})Reject(delegate{Changed(m,pair.Key,pair.Value);});
                    foreach(string name in new[]{"online.cfg","LEIA-ME.txt"}){string key=name=="online.cfg"?"cfg_sha256":"readme_sha256";Reject(delegate{new Updater(Dir("v2-filehash")).Install(Changed(m,key,new string('a',64)),null);});}
                    foreach(string bad in new[]{"../online.cfg","/online.cfg","C:/online.cfg","online.cfg:ads","ONLINE.CFG","online.cfg.","%2e%2e/online.cfg"}){byte[] bytes;using(var buffer=new MemoryStream()){using(var archive=new ZipArchive(buffer,ZipArchiveMode.Create,true)){foreach(string name in m.Files){var e=archive.CreateEntry(name=="online.cfg"?bad:name);using(var file=e.Open()){byte[] content=File.ReadAllBytes(Path.Combine(source,name));file.Write(content,0,content.Length);}}}bytes=buffer.ToArray();}server.Payload=bytes;var d=m.Data();d["sha256"]=HashBytes(bytes);d["package_size"]=(long)bytes.Length;Reject(delegate{new Updater(Dir("v2-traversal")).Install(Manifest.Read(Json.Write(d)),null);});}
                    File.WriteAllText(Path.Combine(source,"extra.dll"),"not approved");Reject(delegate{PackageTool.Package(version,source,Dir("v2-extra"),server.Url+"/package.zip","extra");});
                    var v1=new Updater(Dir("v1-real-mode")){RealOffline=true};var fixture=Offer(server,1);v1.Install(fixture,null);Reject(v1.Play);
                    string profile=Dir("offline-profile"),target=Dir("offline-target");Junction.Make(Path.Combine(profile,"nested"),target);Reject(delegate{Paths.ReviewedProfile(profile);});Check(Directory.GetFileSystemEntries(target).Length==0,"No profile junction traversal");
                    profile=Dir("offline-session");File.WriteAllText(Path.Combine(profile,"account_session.cfg"),"MOCK SESSION; never credentials");Reject(delegate{Paths.ReviewedProfile(profile);});
                    profile=Dir("offline-long");string longDir=Path.Combine(profile,new string('a',70),new string('b',70));Directory.CreateDirectory(Paths.NativePath(longDir));File.WriteAllText(Paths.NativePath(Path.Combine(longDir,"shader.bin")),"MOCK CACHE");Paths.ReviewedProfile(profile);Check(Path.Combine(longDir,"shader.bin").Length>260,"Long generated cache profile reviewed safely");
                });
                Case("clean install check/hash/progress/new/same/lower/rollback/highwater",delegate {
                    var m=Offer(server,1);var u=new Updater(Dir("install"));Check(u.Installed()==null,"Clean install");Check(u.Download.Check(server.Url+"/manifest.json","DEV").Hash==m.Hash,"Manifest feed");long progress=0;u.Install(m,delegate(long n,long total){progress=n;});Check(progress==m.Size,"Progress bytes");Check(u.Installed().Release.Build==1,"Installed 1");ClearTemp(u);
                    Reject(delegate{u.Install(m,null);});var m2=Offer(server,2);u.Install(m2,null);Check(u.Installed().Release.Build==2,"Installed 2");u.Rollback();Check(u.Installed().Release.Build==1,"Known good rollback");Reject(delegate{u.Install(m,null);});Reject(delegate{u.Install(m2,null);});var m3=Offer(server,3);u.Install(m3,null);Check(u.Installed().Release.Build==3,"Upgrade after rollback");
                });
                Case("production trust gate HTTPS and channels",delegate {var m=Offer(server,1);Reject(delegate{new Updater(Dir("https")).Install(Changed(m,"package_url","https://updates.example.com/game.zip"),null);});var d=m.Data();d["release_channel"]="STABLE";d["development_only"]=false;d["game_version"]="1.0.0";d["protocol_version"]=1L;d["rules_version"]=1L;d["package_url"]="https://updates.example.com/game.zip";var prod=Manifest.Read(Json.Write(d));Reject(delegate{new Updater(Dir("prod")).Install(prod,null);});});
                Case("manifest hash/platform/schema/entrypoint/size/date validation",delegate {
                    var m=Offer(server,1);foreach(var pair in new[]{new KeyValuePair<string,object>("sha256","BAD"),new KeyValuePair<string,object>("platform","windows_steam"),new KeyValuePair<string,object>("schema_version",2L),new KeyValuePair<string,object>("entrypoint","calc.exe"),new KeyValuePair<string,object>("package_size",0L),new KeyValuePair<string,object>("package_size",Manifest.MaxPackage+1),new KeyValuePair<string,object>("date","tomorrow")})Reject(delegate{Changed(m,pair.Key,pair.Value);});
                    var bad=Changed(m,"sha256",new string('a',64));var u=new Updater(Dir("bad-hash"));Reject(delegate{u.Install(bad,null);});ClearTemp(u);Check(u.Installed()==null,"Hash fault no installed version");u.Install(m,null);Check(u.Installed()!=null,"Retry valid package");
                });
                foreach(string faultMode in new[]{"partial","corrupt","redirect","oversize","timeout"}) {
                    string mode=faultMode;Case("download "+mode+" cleanup retry preserves old",delegate {
                        server.Mode="ok";var m1=Offer(server,1);var u=new Updater(Dir(mode));u.Download.TimeoutMs=150;u.Download.TotalTimeoutMs=250;u.Install(m1,null);var m2=Offer(server,2);server.Mode=mode;
                        Reject(delegate{u.Install(m2,null);});Check(u.Installed().Release.Build==1,"Failure preserves old");ClearTemp(u);server.Mode="ok";u.Install(m2,null);Check(u.Installed().Release.Build==2,"Retry succeeds");
                    });server.Mode="ok";
                }
                foreach(string point in new[]{"before-download","after-download","after-extract","before-move","after-move","before-pointer"}) {
                    string at=point;Case("simulated disk fault "+at+" rollback/recovery",delegate {
                        var m1=Offer(server,1);var u=new Updater(Dir("disk"));u.Install(m1,null);var m2=Offer(server,2);u.Fault=delegate(string where){if(where==at)throw new IOException("SIMULATED DISK FULL/IO FAULT");};
                        Reject(delegate{u.Install(m2,null);});Check(u.Installed().Release.Build==1,"Atomic pointer preserved");ClearTemp(u);u.Fault=null;u.Install(m2,null);Check(u.Installed().Release.Build==2,"Recovery retry");u.Rollback();Check(u.Installed().Release.Build==1,"Post recovery rollback");
                    });
                }
                Case("archive malicious names/duplicates/link/reparse/extra/corrupt payload",delegate {
                    var m=Offer(server,1);var good=server.Payload;
                    foreach(string name in new[]{"../FRAIHA.exe","/FRAIHA.exe","C:/FRAIHA.exe","..\\FRAIHA.exe","%2e%2e/FRAIHA.exe","FRAIHA.EXE","FRAIHA.exe.","FRAIHA.exe:ads","folder/FRAIHA.exe"}) {
                        server.Payload=Zip(new[]{name,"FRAIHA.pck"},0);var d=m.Data();d["sha256"]=HashBytes(server.Payload);d["package_size"]=(long)server.Payload.Length;var bad=Manifest.Read(Json.Write(d));var u=new Updater(Dir("archive"));Reject(delegate{u.Install(bad,null);});ClearTemp(u);Check(u.Installed()==null,"No malicious installation");
                    }
                    foreach(int attr in new[]{unchecked((int)0xA0000000),0x400,0x10}) {server.Payload=Zip(new[]{"FRAIHA.exe","FRAIHA.pck"},attr);var d=m.Data();d["sha256"]=HashBytes(server.Payload);d["package_size"]=(long)server.Payload.Length;var u=new Updater(Dir("archive-link"));Reject(delegate{u.Install(Manifest.Read(Json.Write(d)),null);});ClearTemp(u);}
                    foreach(string[] names in new[]{new[]{"FRAIHA.exe","FRAIHA.exe"},new[]{"FRAIHA.exe","FRAIHA.pck","evil.bat"},new[]{"FRAIHA.exe"}}) {server.Payload=Zip(names,0);var d=m.Data();d["sha256"]=HashBytes(server.Payload);d["package_size"]=(long)server.Payload.Length;Reject(delegate{new Updater(Dir("archive-count")).Install(Manifest.Read(Json.Write(d)),null);});}
                    // Valid names and lengths but malicious payload: per-file digest must still fail.
                    server.Payload=Zip(new[]{"FRAIHA.exe","FRAIHA.pck"},0);var data=m.Data();data["sha256"]=HashBytes(server.Payload);data["package_size"]=(long)server.Payload.Length;data["exe_sha256"]=new string('a',64);Reject(delegate{new Updater(Dir("file-hash")).Install(Manifest.Read(Json.Write(data)),null);});server.Payload=good;
                });
                Case("operation lock and game-running PLAY actual Windows stub",delegate {
                    var m=Offer(server,1);var u=new Updater(Dir("play"));u.Install(m,null);using(u.Acquire())Reject(delegate{u.Installed();});
                    var task=Task.Factory.StartNew(u.Play);string marker=Path.Combine(u.Root,"versions",m.Release.Id,"stub-launched.txt");var watch=Stopwatch.StartNew();while(!File.Exists(marker) && watch.ElapsedMilliseconds<2000)Thread.Sleep(10);
                    Check(File.Exists(marker),"Fixed executable launched real process");var m2=Offer(server,2);Reject(delegate{u.Install(m2,null);});task.Wait();Check(u.Installed().Release.Build==1,"PLAY preserves payload");u.Install(m2,null);
                    string exe=Path.Combine(u.Root,"versions",m2.Release.Id,"FRAIHA.exe");using(var external=Process.Start(new ProcessStartInfo(exe){UseShellExecute=false})) {Reject(delegate{u.Install(Offer(server,3),null);});external.WaitForExit();}
                });
                Case("real Windows junction root/versions/payload/pointer rejection",delegate {
                    string target=Dir("junction-target"),parent=Dir("junction-parent"),link=Path.Combine(parent,"link");Junction.Make(link,target);Reject(delegate{new Updater(link);});
                    var u=new Updater(Dir("junction-install"));var m=Offer(server,1);Junction.Make(Path.Combine(u.Root,"versions"),target);Reject(delegate{u.Install(m,null);});Check(Directory.GetFileSystemEntries(target).Length==0,"No writes through junction");
                    var u2=new Updater(Dir("junction-payload"));u2.Install(m,null);string payload=Path.Combine(u2.Root,"versions",m.Release.Id,"FRAIHA.pck");File.Delete(payload);Junction.Make(payload,target);Reject(delegate{u2.Play();});
                    var u3=new Updater(Dir("junction-state"));Junction.Make(Path.Combine(u3.Root,"state.json"),target);Reject(delegate{u3.Install(m,null);});
                });
                Case("installed tamper prevents PLAY and rollback",delegate {var m=Offer(server,1);var u=new Updater(Dir("tamper"));u.Install(m,null);var m2=Offer(server,2);u.Install(m2,null);File.AppendAllText(Path.Combine(u.Root,"versions",m.Release.Id,"FRAIHA.pck"),"tamper");Reject(u.Rollback);File.AppendAllText(Path.Combine(u.Root,"versions",m2.Release.Id,"FRAIHA.pck"),"tamper");Reject(u.Play);});
                Case("IPv6 manifest roundtrip preserves literal loopback",delegate {var m=Offer(server,1);m.Url=Manifest.SafeUrl("http://[::1]:8765/package.zip","DEV");var round=Manifest.Read(Json.Write(m.Data()));round.RequireDevTrust();Check(round.Url.IsLoopback,"IPv6 URI remains loopback");});
                Case("automatic flow clean/new/same/rollback and lower rejects",delegate {
                    var m=Offer(server,1);var u=new Updater(Dir("auto"));var flow=new LauncherFlow(u);string feed=server.Url+"/manifest.json";
                    flow.CheckUpdatePlay(feed,null,null,null);string marker=Path.Combine(u.Root,"versions",m.Release.Id,"stub-launched.txt");Check(File.Exists(marker),"Auto clean install launches");File.Delete(marker);
                    flow.CheckUpdatePlay(feed,null,null,null);Check(File.Exists(marker),"Same build skip install launches");
                    var m2=Offer(server,2);flow.CheckUpdatePlay(feed,null,null,null);Check(u.Installed().Release.Build==2,"Auto update applies before PLAY");string marker2=Path.Combine(u.Root,"versions",m2.Release.Id,"stub-launched.txt");Check(File.Exists(marker2),"New build launched");File.Delete(marker2);Offer(server,1);Reject(delegate{flow.CheckUpdatePlay(feed,null,null,null);});Check(!File.Exists(marker2),"Downgrade must not launch old/current");
                });
                Case("automatic flow check/download/hash errors never PLAY",delegate {
                    var m=Offer(server,1);var u=new Updater(Dir("auto-failure"));u.Install(m,null);var flow=new LauncherFlow(u);string marker=Path.Combine(u.Root,"versions",m.Release.Id,"stub-launched.txt");
                    var m2=Offer(server,2);server.Mode="corrupt";Reject(delegate{flow.CheckUpdatePlay(server.Url+"/manifest.json",null,null,null);});Check(!File.Exists(marker),"Manifest error must not launch");server.Mode="ok";
                    server.ManifestJson=Json.Write(Changed(m2,"sha256",new string('a',64)).Data());Reject(delegate{flow.CheckUpdatePlay(server.Url+"/manifest.json",null,null,null);});Check(!File.Exists(marker),"Hash error must not launch known-good");ClearTemp(u);
                    server.ManifestJson=Json.Write(Changed(m,"sha256",new string('a',64)).Data());Reject(delegate{flow.CheckUpdatePlay(server.Url+"/manifest.json",null,null,null);});Check(!File.Exists(marker),"Conflicting same build must not launch");
                });
                Case("automatic WinForms startup checks applies launches",delegate {var m=Offer(server,1);string install=Dir("ui-auto");using(var form=new LauncherForm(install,true,server.Url+"/manifest.json")){form.Show();PumpUntil(delegate{return ButtonNamed(form,"Check / Retry").Enabled;});Check(LabelContains(form,"Installed: 0.0.0 / build 1"),"Startup installed: "+Labels(form));Check(File.Exists(Path.Combine(install,"versions",m.Release.Id,"stub-launched.txt")),"Startup launched fixed stub");form.Close();}});
                Case("UI actual WinForms check/update/PLAY/error/retry/render",delegate {
                    Application.EnableVisualStyles();var m=Offer(server,1);string install=Dir("ui");using(var form=new LauncherForm(install)) {
                        form.Show();Application.DoEvents();Button check=ButtonNamed(form,"Check / Retry"),update=ButtonNamed(form,"Download / Update"),play=ButtonNamed(form,"PLAY"),rollback=ButtonNamed(form,"Rollback");
                        foreach(Control c in form.Controls)if(c is TextBox && !((TextBox)c).Multiline)((TextBox)c).Text=server.Url+"/manifest.json";
                        check.PerformClick();PumpUntil(delegate{return check.Enabled;});Check(LabelContains(form,"Available: 0.0.0 / build 1"),"UI check available");
                        update.PerformClick();PumpUntil(delegate{return check.Enabled;});Check(LabelContains(form,"Installed: 0.0.0 / build 1"),"UI installed: "+Labels(form));
                        play.PerformClick();PumpUntil(delegate{return File.Exists(Path.Combine(install,"versions",m.Release.Id,"stub-launched.txt"));});Check(!update.Enabled,"UI blocks update during PLAY");PumpUntil(delegate{return check.Enabled;});
                        rollback.PerformClick();PumpUntil(delegate{return check.Enabled;});Check(LabelContains(form,"Error:"),"UI error status");
                        Offer(server,2);check.PerformClick();PumpUntil(delegate{return check.Enabled;});update.PerformClick();PumpUntil(delegate{return check.Enabled;});Check(LabelContains(form,"Installed: 0.0.0 / build 2"),"UI retry/update");
                        using(var bitmap=new System.Drawing.Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,new System.Drawing.Rectangle(0,0,bitmap.Width,bitmap.Height));bitmap.Save(Path.Combine(root,"launcher-ui.png"));}form.Close();
                    }
                });
            }
            lines.Add("SUMMARY "+passed+" passed, "+failed+" failed; Windows .NET Framework actual runtime; TCP loopback mocks and C# game stub, NOT Godot QA.");File.WriteAllLines(Path.Combine(root,"results.txt"),lines.ToArray());Console.WriteLine(lines[lines.Count-1]);Console.WriteLine("Evidence: "+root);return failed==0?0:1;
        }
        static string DirUnderBase() {string p=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../qa-"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N")));Directory.CreateDirectory(p);return p;}
        static Button ButtonNamed(Form form,string name) {foreach(Control c in form.Controls)if(c is Button && c.Text==name)return (Button)c;throw new Exception("Missing UI button "+name);}
        static bool LabelContains(Form form,string text) {foreach(Control c in form.Controls)if(c is Label && c.Text.Contains(text))return true;return false;}
        static string Labels(Form form) {var s=new StringBuilder();foreach(Control c in form.Controls)if(c is Label)s.Append(c.Text+" | ");return s.ToString();}
        static void PumpUntil(Func<bool> ready) {var watch=Stopwatch.StartNew();Application.DoEvents();while(!ready()){Application.DoEvents();if(watch.ElapsedMilliseconds>4000)throw new TimeoutException("UI action did not complete");Thread.Sleep(10);}Application.DoEvents();}
        static byte[] Zip(string[] names,int attributes) {
            // Keep sizes/digests otherwise valid so malicious-name/link assertions exercise those gates.
            byte[] exe=File.ReadAllBytes(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"FRAIHA.exe")),pck=Encoding.UTF8.GetBytes("NOT A GODOT PCK; LOCAL DEV STUB FIXTURE");
            using(var ms=new MemoryStream()) {using(var z=new ZipArchive(ms,ZipArchiveMode.Create,true))for(int i=0;i<names.Length;i++){var e=z.CreateEntry(names[i]);e.ExternalAttributes=attributes;byte[] payload=i==0?exe:pck;using(var s=e.Open())s.Write(payload,0,payload.Length);}return ms.ToArray();}
        }
        static string HashBytes(byte[] bytes) {using(var h=System.Security.Cryptography.SHA256.Create())return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
    }
    public static class Junction {
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
        [DllImport("kernel32.dll",SetLastError=true)]static extern bool DeviceIoControl(SafeFileHandle h,uint code,byte[] input,int size,IntPtr output,int outputSize,out int returned,IntPtr overlap);
        public static void Make(string path,string target) {
            Directory.CreateDirectory(path);byte[] substitute=Encoding.Unicode.GetBytes(@"\??\"+Path.GetFullPath(target)),print=Encoding.Unicode.GetBytes(Path.GetFullPath(target));
            int dataLength=8+substitute.Length+2+print.Length+2;byte[] buffer=new byte[8+dataLength];
            Array.Copy(BitConverter.GetBytes(0xA0000003u),0,buffer,0,4);Array.Copy(BitConverter.GetBytes((ushort)dataLength),0,buffer,4,2);
            Array.Copy(BitConverter.GetBytes((ushort)substitute.Length),0,buffer,10,2);Array.Copy(BitConverter.GetBytes((ushort)(substitute.Length+2)),0,buffer,12,2);Array.Copy(BitConverter.GetBytes((ushort)print.Length),0,buffer,14,2);Array.Copy(substitute,0,buffer,16,substitute.Length);Array.Copy(print,0,buffer,16+substitute.Length+2,print.Length);
            using(var h=CreateFile(path,0x40000000,0,IntPtr.Zero,3,0x02200000,IntPtr.Zero)) {int n;if(h.IsInvalid || !DeviceIoControl(h,0x000900A4,buffer,buffer.Length,IntPtr.Zero,0,out n,IntPtr.Zero))throw new IOException("Junction creation failed "+Marshal.GetLastWin32Error());}
        }
    }
}
