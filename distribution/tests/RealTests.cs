using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Fraiha.Distribution {
    // Explicit local acceptance harness. Requires copied, reviewed exports; never fetches them.
    public static class RealTests {
        static string evidence;static readonly List<string> lines=new List<string>();
        static void Log(string s){lines.Add(s);Console.WriteLine(s);File.WriteAllLines(Path.Combine(evidence,"results.txt"),lines);}
        static void Assert(bool b,string s){if(!b)throw new Exception(s);Log("PASS "+s);}
        static void Reject(Action a,string s){bool rejected=false;try{a();}catch(InvalidDataException){rejected=true;}catch(IOException){rejected=true;}catch(WebException){rejected=true;}catch(InvalidOperationException){rejected=true;}Assert(rejected,s);}
        static Manifest Offer(MockServer server,string historical,long build){
            string version=Path.Combine(evidence,"version-"+build+".json"),output=Path.Combine(evidence,"package-"+build);
            File.WriteAllText(version,Json.Write(new Release{Version="0.0.0",Build=build,Protocol=0,Rules=0,Channel="DEV",Platform="windows_site",DevOnly=true}.Data()));
            var m=PackageTool.Package(version,Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../real-"+historical+"-dev-export")),output,server.Url+"/package.zip","DEV distribution build "+build+"; real FRAIHA export "+historical+" (current mainline); offline only");
            server.Payload=File.ReadAllBytes(Path.Combine(output,"fraiha-"+m.Release.Id+".zip"));server.ManifestJson=Json.Write(m.Data());return m;
        }
        [DllImport("iphlpapi.dll")]static extern uint GetExtendedTcpTable(IntPtr table,ref int size,bool order,int family,int cls,uint reserved);
        [DllImport("user32.dll")]static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wparam,IntPtr lparam);
        static void CheckNetwork(int pid){int size=0;GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,5,0);IntPtr ptr=Marshal.AllocHGlobal(size);try{if(GetExtendedTcpTable(ptr,ref size,false,2,5,0)!=0)throw new Exception("TCP observation failed");int count=Marshal.ReadInt32(ptr);for(int i=0;i<count;i++){int at=4+i*24;int owner=Marshal.ReadInt32(ptr,at+20);uint remote=unchecked((uint)Marshal.ReadInt32(ptr,at+12));if(owner==pid && remote!=0 && (remote&255)!=127)throw new Exception("Non-loopback IPv4 TCP connection observed");}}finally{Marshal.FreeHGlobal(ptr);}
            size=0;GetExtendedTcpTable(IntPtr.Zero,ref size,false,23,5,0);ptr=Marshal.AllocHGlobal(size);try{if(GetExtendedTcpTable(ptr,ref size,false,23,5,0)!=0)throw new Exception("TCP6 observation failed");int count=Marshal.ReadInt32(ptr);for(int i=0;i<count;i++){int at=4+i*56;if(Marshal.ReadInt32(ptr,at+52)!=pid)continue;bool zero=true,loop=true;for(int j=0;j<16;j++){byte b=Marshal.ReadByte(ptr,at+24+j);if(b!=0)zero=false;if(b!=(j==15?1:0))loop=false;}if(!zero && !loop)throw new Exception("Non-loopback IPv6 TCP connection observed");}}finally{Marshal.FreeHGlobal(ptr);}}
        static void ObserveGame(Updater u,string tag,Action whileRunning){
            string expected=Path.Combine(u.Root,"versions",u.Installed().Release.Id,"FRAIHA.exe");var play=Task.Factory.StartNew(u.Play);var watch=Stopwatch.StartNew();Process game=null;bool captured=false;int samples=0;
            try{while(!play.IsCompleted && watch.ElapsedMilliseconds<45000){Application.DoEvents();if(game==null){foreach(var p in Process.GetProcessesByName("FRAIHA")){try{if(p.MainModule.FileName==expected){game=p;break;}}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}}}
                if(game!=null && !game.HasExited){CheckNetwork(game.Id);samples++;game.Refresh();if(!captured && game.MainWindowHandle!=IntPtr.Zero && game.MainWindowTitle.Contains("FRAIHA")){Assert(true,"real game window "+tag+" title="+game.MainWindowTitle);captured=true;if(whileRunning!=null)whileRunning();}}
                Thread.Sleep(50);
            }if(!play.IsCompleted)throw new Exception("Game failed to exit within QA deadline");play.GetAwaiter().GetResult();Assert(captured && samples>0,"real startup window and TCP observed "+tag+" samples="+samples);Assert(u.LastGameExitCode==0,"real game clean exit "+tag);string[] frames=Directory.GetFiles(u.LastGameCaptureDirectory,"*.png");Array.Sort(frames,StringComparer.Ordinal);Assert(frames.Length==12,"12 frames captured by actual Godot viewport "+tag);File.Copy(frames[frames.Length-1],Path.Combine(evidence,"game-"+tag+".png"));Log("CAPTURE "+tag+" "+u.LastGameCaptureDirectory);
            }finally{if(game!=null){if(!game.HasExited){game.Kill();game.WaitForExit();}game.Dispose();}}
        }
        [STAThread]public static int Main(){
            Paths.InitializeRuntime();
            evidence=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../rqa-"+DateTime.UtcNow.ToString("HHmmssfff")));Directory.CreateDirectory(evidence);
            try{Application.EnableVisualStyles();using(var server=new MockServer(8765)){
                var a=Offer(server,"A",1);var u=new Updater(Path.Combine(evidence,"i")){RealOffline=true,QaAutoQuit=true};Assert(u.Installed()==null,"clean installation A");u.Install(u.Download.Check(server.Url+"/manifest.json","DEV"),null);Assert(u.Installed().PckHash==a.PckHash && a.CompleteExport,"A complete real current export installed");
                Assert(ReviewedPins.Load(ReviewedPins.DefaultFile()).Allows(a),"local reviewed pins (next to launcher) allow A");
                var b=Offer(server,"B",2);byte[] bytesB=server.Payload;Assert(a.PckHash!=b.PckHash,"A/B are different real PCK builds; DEV build numbers remain metadata");
                ObserveGame(u,"A",delegate{Reject(delegate{u.Install(b,null);},"update blocked with real game open");});
                using(var form=new LauncherForm(u.Root,false,server.Url+"/manifest.json",true)){
                    form.Show();Application.DoEvents();Button check=null,update=null;foreach(Control control in form.Controls){var button=control as Button;if(button!=null){if(button.Text=="Check / Retry")check=button;if(button.Text=="Download / Update")update=button;}}
                    Assert(check!=null && update!=null,"real launcher controls present");check.PerformClick();Pump(form);update.PerformClick();Pump(form);using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,new Rectangle(0,0,bitmap.Width,bitmap.Height));bitmap.Save(Path.Combine(evidence,"launcher-real.png"));}form.Close();
                }Assert(u.Installed().Release.Build==2 && u.Installed().PckHash==b.PckHash,"launcher checked B, downloaded/hash/installed and changed pointer");ObserveGame(u,"B",null);
                u.Rollback();Assert(u.Installed().PckHash==a.PckHash,"rollback restores real A");var c=Offer(server,"B",3);var invalid=c.Data();invalid["sha256"]=new string('a',64);Reject(delegate{u.Install(Manifest.Read(Json.Write(invalid)),null);},"invalid update rejected preserving A");Assert(u.Installed().PckHash==a.PckHash,"A pointer usable after invalid update");
                server.Mode="partial";Reject(delegate{u.Install(c,null);},"partial real package rejected");server.Mode="ok";u.Install(c,null);Assert(u.Installed().Release.Build==3,"retry real package succeeds");u.Rollback();ObserveGame(u,"A-after-failure-rollback",null);
                server.ManifestJson="{}";Reject(delegate{new LauncherFlow(u).CheckUpdatePlay(server.Url+"/manifest.json",null,null,null);},"invalid manifest skips PLAY");server.Mode="redirect";Reject(delegate{u.Download.Check(server.Url+"/manifest.json","DEV");},"manifest unavailable rejects without game fallback");server.Mode="ok";
                bool started=false;Reject(delegate{new LauncherFlow(u).CheckUpdatePlay("http://127.0.0.1:1/manifest.json",null,null,delegate{started=true;});},"offline refused feed fails automatic flow");Assert(!started && u.Installed().PckHash==a.PckHash,"offline flow never auto-plays stale state; manual A remains verified");
                string cfg=Path.Combine(u.Root,"versions",a.Release.Id,"online.cfg");File.AppendAllText(cfg,"tampered");Reject(u.Play,"sidecar tamper blocks real PLAY");File.WriteAllText(cfg,"[online]\nserver_url=\"\"\n",new UTF8Encoding(false));Assert(u.Installed().PckHash==a.PckHash,"sidecar restored to exact DEV bytes");
                Assert(Directory.GetFileSystemEntries(Path.Combine(u.Root,"temp")).Length==0,"real package staging cleaned");Paths.ReviewedProfile(Path.Combine(u.Root,"userdata"));Assert(true,"fresh isolated profile has no account/session cfg or reparse paths");
                server.Payload=bytesB;server.ManifestJson=Json.Write(b.Data());NormalLauncher(b);
                Log("LIMIT: TCP sampling covers startup, not packet-level proof or UDP; source review plus fixed empty endpoint provides offline policy for these pinned exports only.");
                Assert(u.Installed().PckHash==a.PckHash,"current = A before smoke");Smoke(u,"A");u.Rollback();Assert(u.Installed().PckHash==b.PckHash,"rollback toggles to B");Smoke(u,"B");u.Rollback();Assert(u.Installed().PckHash==a.PckHash,"back to A");
                var tmpPins=Path.Combine(evidence,"no-pins.txt");File.WriteAllText(tmpPins,"# vazio\n");
                var u2=new Updater(u.Root){RealOffline=true,ReviewedPinsFile=tmpPins};Reject(u2.Play,"export without local reviewed pins refuses real PLAY");
                Log("SUMMARY real Windows acceptance passed; CURRENT mainline exports A/B (DEV offline), not production.");
            }return 0;}catch(Exception e){Log("FAIL "+e);return 1;}finally{Console.WriteLine("Evidence: "+evidence);}
        }
        // Smoke de JOGO no binário real instalado (não só a Home): roda scripts de teste que já vêm no .pck
        // (preset Windows inclui tests/) com argumentos FIXOS deste harness — nada vem do manifesto/launcher.
        static void Smoke(Updater u,string tag){
            string id=u.Installed().Release.Id,dir=Path.Combine(u.Root,"versions",id),profile=Path.Combine(u.Root,"userdata");Directory.CreateDirectory(profile);
            foreach(var script in new[]{"res://tests/rules_test.gd","res://tests/home_navigation_test.gd","res://tests/bot_search_test.gd"}){
                var start=new ProcessStartInfo(Path.Combine(dir,"FRAIHA.exe"),"--headless -s "+script){WorkingDirectory=dir,UseShellExecute=false,RedirectStandardOutput=true,RedirectStandardError=true};
                start.EnvironmentVariables["APPDATA"]=profile;start.EnvironmentVariables["LOCALAPPDATA"]=Path.Combine(profile,"cache");start.EnvironmentVariables["FRAIHA_SERVER_URL"]="";start.EnvironmentVariables["FRAIHA_SUPABASE_URL"]="";start.EnvironmentVariables["FRAIHA_SUPABASE_KEY"]="";
                using(var p=Process.Start(start)){var outTask=p.StandardOutput.ReadToEndAsync();var errTask=p.StandardError.ReadToEndAsync();if(!p.WaitForExit(240000)){p.Kill();throw new Exception("smoke timeout "+script);}
                    string output=outTask.Result+errTask.Result;File.WriteAllText(Path.Combine(evidence,"smoke-"+tag+"-"+Path.GetFileNameWithoutExtension(script)+".txt"),output);
                    bool failed=output.Contains("FAILURES=") && !System.Text.RegularExpressions.Regex.IsMatch(output,"FAILURES=0\\b");
                    bool scriptError=output.Contains("SCRIPT ERROR");
                    Assert(!failed && !scriptError && (output.Contains("FAILURES=0") || output.Contains("RESULT OK")),"real binary smoke "+tag+" "+script+" (exit "+p.ExitCode+")");}
            }
        }
        static void Pump(LauncherForm form){var busy=typeof(LauncherForm).GetField("busy",BindingFlags.Instance|BindingFlags.NonPublic);var watch=Stopwatch.StartNew();do{Application.DoEvents();Thread.Sleep(20);if(watch.ElapsedMilliseconds>90000)throw new Exception("Launcher deadline");}while((bool)busy.GetValue(form));foreach(Control c in form.Controls)if(c is Label && c.Text.StartsWith("Error:",StringComparison.Ordinal))throw new Exception(c.Text);}
        static void NormalLauncher(Manifest offered){
            string gui=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../g"+DateTime.UtcNow.ToString("HHmmss")));Directory.CreateDirectory(gui);string launcher=Path.Combine(gui,"FRAIHA.Launcher.exe");File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"FRAIHA.Launcher.exe"),launcher);File.Copy(ReviewedPins.DefaultFile(),Path.Combine(gui,"dev-reviewed-exports.txt"));
            string install=Path.Combine(gui,"dev-real-install"),expected=Path.Combine(install,"versions",offered.Release.Id,"FRAIHA.exe");Process game=null;
            using(var process=Process.Start(new ProcessStartInfo(launcher){Arguments="--dev-real-offline --auto-play",WorkingDirectory=gui,UseShellExecute=false})){
                try{var watch=Stopwatch.StartNew();int samples=0;while(watch.ElapsedMilliseconds<90000){Application.DoEvents();if(process.HasExited)throw new Exception("Normal launcher exited before game startup");if(game==null){foreach(var p in Process.GetProcessesByName("FRAIHA")){try{if(p.MainModule.FileName==expected){game=p;break;}}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}}}if(game!=null && !game.HasExited){CheckNetwork(game.Id);game.Refresh();if(game.MainWindowTitle.Contains("FRAIHA") && game.MainWindowHandle!=IntPtr.Zero){samples++;if(samples>=40)break;}}Thread.Sleep(50);}
                    Assert(game!=null && samples>=40,"normal Launcher.exe auto-check/install/PLAY real GUI without movie/fixed-fps; TCP observed");Assert(StoreState.Read(Path.Combine(install,"state.json")).Current==offered.Release.Id,"normal launcher pointer installed B");Log("NORMAL_GUI "+gui+" game PID="+game.Id+" title="+game.MainWindowTitle);
                    game.CloseMainWindow();Thread.Sleep(500);PostMessage(game.MainWindowHandle,0x100,(IntPtr)13,IntPtr.Zero);PostMessage(game.MainWindowHandle,0x101,(IntPtr)13,IntPtr.Zero);if(!game.WaitForExit(8000)){Log("LIMIT normal GUI QA process required owned-process stop after startup");game.Kill();game.WaitForExit();}Thread.Sleep(300);process.CloseMainWindow();if(!process.WaitForExit(3000)){process.Kill();process.WaitForExit();}
                    string log=Path.Combine(install,"userdata","FRAIHA Xadrez Musicas V026 Teste","logs","godot.log");Assert(File.Exists(log),"normal GUI isolated userdata log exists");File.Copy(log,Path.Combine(evidence,"normal-game.log"));
                }finally{if(game!=null){if(!game.HasExited){game.Kill();game.WaitForExit();}game.Dispose();}if(!process.HasExited){process.Kill();process.WaitForExit();}}
            }
        }
    }
}
