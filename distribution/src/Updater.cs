using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Text;

namespace Fraiha.Distribution {
    public static class Paths {
        public static void InitializeRuntime(){AppContext.SetSwitch("Switch.System.IO.UseLegacyPathHandling",false);AppContext.SetSwitch("Switch.System.IO.BlockLongPaths",false);}
        public static string NativePath(string path){return path.Length>=248 && !path.StartsWith(@"\\",StringComparison.Ordinal)?@"\\?\"+path:path;}
        public static void ReviewedProfile(string root){
            NoReparse(root);if(!Directory.Exists(root))return;var pending=new Stack<string>();pending.Push(root);
            while(pending.Count>0){string dir=pending.Pop();NoReparse(dir);foreach(string child in Directory.GetFileSystemEntries(NativePath(dir))){NoReparse(child);if(Directory.Exists(NativePath(child)))pending.Push(child);else {string name=Path.GetFileName(child);if(name.Equals("account_session.cfg",StringComparison.OrdinalIgnoreCase) || name.Equals("guest_session.cfg",StringComparison.OrdinalIgnoreCase) || name.Equals("online_session.cfg",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("DEV offline profile must not contain authentication/session files");}}}
        }
        public static void NoReparse(string path) {
            string full=Path.GetFullPath(path); string current=Path.GetPathRoot(full);
            foreach(string part in full.Substring(current.Length).Split(Path.DirectorySeparatorChar)) {
                if(part.Length==0)continue; current=Path.Combine(current,part);
                try { if((File.GetAttributes(NativePath(current))&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("Reparse point refused: "+current); }
                catch(FileNotFoundException) {} catch(DirectoryNotFoundException) {}
            }
        }
        public static string Child(string root,string relative) {
            if(Path.IsPathRooted(relative) || relative.Contains("..") || relative.Contains(":") || relative.Contains("%"))throw new InvalidDataException("Unsafe local path");
            string full=Path.GetFullPath(Path.Combine(root,relative)); string prefix=Path.GetFullPath(root).TrimEnd('\\')+"\\";
            if(!full.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Outside install root"); NoReparse(full); return full;
        }
    }
    public class HttpDownload {
        public int TimeoutMs=5000; public int TotalTimeoutMs=60000;
        public void Get(Uri url,string channel,Stream output,long limit,long expected,Action<long,long> progress) {
            Manifest.SafeUrl(url.OriginalString,channel);
            var request=(HttpWebRequest)WebRequest.Create(url); request.AllowAutoRedirect=false;request.Timeout=TimeoutMs;request.ReadWriteTimeout=TimeoutMs;request.Proxy=null;request.Credentials=null;request.UseDefaultCredentials=false;request.AutomaticDecompression=DecompressionMethods.None;
            var watch=Stopwatch.StartNew();
            using(var response=(HttpWebResponse)request.GetResponse()) {
                if(response.StatusCode!=HttpStatusCode.OK)throw new InvalidDataException("HTTP status/redirect rejected");
                if(response.ContentLength>limit || (expected>=0 && response.ContentLength>=0 && response.ContentLength!=expected))throw new InvalidDataException("HTTP size mismatch");
                using(var input=response.GetResponseStream()) {
                    input.ReadTimeout=TimeoutMs;byte[] buffer=new byte[32768];long total=0;int read;
                    while((read=input.Read(buffer,0,buffer.Length))>0) {
                        if(watch.ElapsedMilliseconds>TotalTimeoutMs)throw new TimeoutException("Total download timeout"); total+=read;
                        if(total>limit || (expected>=0 && total>expected))throw new InvalidDataException("Download size exceeded");
                        output.Write(buffer,0,read); if(progress!=null)progress(total,expected);
                    }
                    if(expected>=0 && total!=expected)throw new InvalidDataException("Interrupted download");
                }
            }
        }
        public Manifest Check(string feed,string channel) {
            var url=Manifest.SafeUrl(feed,channel); using(var m=new MemoryStream()) {
                Get(url,channel,m,32768,-1,null);
                try{return Manifest.Read(new UTF8Encoding(false,true).GetString(m.ToArray()));}
                catch(DecoderFallbackException e){throw new InvalidDataException("Manifest is not valid UTF-8",e);}
            }
        }
    }
    public sealed class StoreState {
        public string Current,Previous,HighVersion; public long HighBuild;
        public static StoreState Read(string path) {
            var d=Json.Read(Json.ReadFile(path));Json.Keys(d,"current,previous,high_game_version,high_build,channel,platform");
            if(Json.Text(d,"channel")!="DEV" || Json.Text(d,"platform")!="windows_site")throw new InvalidDataException("Store identity mismatch");
            var s=new StoreState{Current=Json.Text(d,"current"),Previous=Json.Text(d,"previous"),HighVersion=Json.Text(d,"high_game_version"),HighBuild=Json.Number(d,"high_build",2100000000)};
            ValidateId(s.Current);if(s.Previous!="")ValidateId(s.Previous);Release.CompareVersion(s.HighVersion,s.HighVersion);if(s.HighBuild<1)throw new InvalidDataException("High water mark");return s;
        }
        public static void ValidateId(string id) {
            if(!System.Text.RegularExpressions.Regex.IsMatch(id,@"^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})-([1-9][0-9]{0,9})$"))throw new InvalidDataException("Unsafe installed ID");
        }
        public string Encode() {return Json.Write(new Dictionary<string,object>{{"current",Current},{"previous",Previous},{"high_game_version",HighVersion},{"high_build",HighBuild},{"channel","DEV"},{"platform","windows_site"}});}
    }
    public sealed class Updater {
        public readonly string Root;public readonly HttpDownload Download=new HttpDownload();
        public Action<string> Fault; // Deterministic tests only; not exposed to feed or command line.
        public Updater(string root) {
            if(!Path.IsPathRooted(root) || root.StartsWith(@"\\",StringComparison.Ordinal))throw new InvalidDataException("Absolute local drive root required");
            Root=Path.GetFullPath(root).TrimEnd('\\'); if(Root==Path.GetPathRoot(Root).TrimEnd('\\'))throw new InvalidDataException("Drive root forbidden"); Paths.NoReparse(Root); Directory.CreateDirectory(Root);
        }
        string P(string rel) {return Paths.Child(Root,rel);}
        void At(string point) {if(Fault!=null)Fault(point);}
        public IDisposable Acquire() {
            Paths.NoReparse(Root);
            if(Process.GetProcessesByName("FRAIHA").Length>0)throw new IOException("Game running: close FRAIHA before update");
            return new FileStream(P("operation.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        }
        StoreState State() {return File.Exists(P("state.json"))?StoreState.Read(P("state.json")):null;}
        public Manifest Installed() {using(Acquire()) {var state=State();return state==null?null:VerifyInstalled(state.Current);}}
        Manifest VerifyInstalled(string id) {
            StoreState.ValidateId(id);string dir=P("versions\\"+id);
            var m=Manifest.Read(Json.ReadFile(Paths.Child(dir,"manifest.json")));m.RequireDevTrust();
            if(m.Release.Id!=id)throw new InvalidDataException("Installed identity mismatch");
            foreach(string name in m.Files)VerifyFile(Paths.Child(dir,name),m.FileSize(name),m.FileHash(name));return m;
        }
        static void VerifyFile(string path,long size,string hash) {Paths.NoReparse(path); if(new FileInfo(path).Length!=size || Manifest.Sha(path)!=hash)throw new InvalidDataException("Installed file/hash mismatch");}
        void WriteState(StoreState state) {
            string next=P("state.next"); if(File.Exists(next)) {Paths.NoReparse(next);File.Delete(next);}
            using(var file=new FileStream(next,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {byte[] bytes=Encoding.UTF8.GetBytes(state.Encode());file.Write(bytes,0,bytes.Length);file.Flush(true);}
            At("before-pointer");
            if(File.Exists(P("state.json")))File.Replace(next,P("state.json"),P("state.backup"),true);else File.Move(next,P("state.json"));
            // Commit point: no fallible work afterwards. A process crash here leaves a complete new state.
        }
        public void Install(Manifest m,Action<long,long> progress) {
            m=Manifest.Read(Json.Write(m.Data()));
            m.RequireDevTrust(); using(Acquire()) {
                var s=State(); if(s!=null) {
                    VerifyInstalled(s.Current);
                    if(m.Release.Build<=s.HighBuild || Release.CompareVersion(m.Release.Version,s.HighVersion)<0)throw new InvalidDataException("Same/lower release rejected by high-water mark");
                }
                if(m.Release.Platform!="windows_site" || m.Release.Channel!="DEV")throw new InvalidDataException("Wrong store");
                string version=P("versions\\"+m.Release.Id);
                // Crash recovery: reuse only a completely verified orphan identical to the offered manifest.
                if(Directory.Exists(version)) {
                    var orphan=VerifyInstalled(m.Release.Id);
                    if(Json.Write(orphan.Data())!=Json.Write(m.Data()))throw new IOException("Conflicting preserved version directory");
                    WriteState(new StoreState{Current=m.Release.Id,Previous=s==null?"":s.Current,HighVersion=m.Release.Version,HighBuild=m.Release.Build});return;
                }
                string stage=P("temp\\"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(stage);
                try {
                    string partial=Paths.Child(stage,"package.partial");
                    At("before-download");using(var file=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {Download.Get(m.Url,"DEV",file,Manifest.MaxPackage,m.Size,progress);file.Flush(true);}
                    if(Manifest.Sha(partial)!=m.Hash)throw new InvalidDataException("Package SHA256 mismatch");At("after-download");
                    string payload=Paths.Child(stage,"payload");Directory.CreateDirectory(payload); Extract(partial,payload,m);At("after-extract");
                    File.WriteAllText(Paths.Child(payload,"manifest.json"),Json.Write(m.Data()),new UTF8Encoding(false));
                    Directory.CreateDirectory(P("versions"));At("before-move");Directory.Move(payload,version);At("after-move");
                    // Remove private download before pointer commit so cleanup failure cannot masquerade as failed install.
                    RemoveStage(stage);stage=null;
                    WriteState(new StoreState{Current=m.Release.Id,Previous=s==null?"":s.Current,HighVersion=m.Release.Version,HighBuild=m.Release.Build});
                } finally {if(stage!=null && Directory.Exists(stage))RemoveStage(stage);}
            }
        }
        void RemoveStage(string stage) {
            Paths.NoReparse(stage); foreach(string child in Directory.GetFileSystemEntries(stage)) {
                Paths.NoReparse(child);if(Directory.Exists(child)) {foreach(string f in Directory.GetFileSystemEntries(child)) {Paths.NoReparse(f);if(Directory.Exists(f))throw new InvalidDataException("Unexpected staging directory");File.Delete(f);}Directory.Delete(child);}
                else File.Delete(child);
            } Directory.Delete(stage);
        }
        public static void Extract(string zip,string destination,Manifest m) {
            Paths.NoReparse(zip);Paths.NoReparse(destination);
            using(var archive=ZipFile.OpenRead(zip)) {
                if(archive.Entries.Count!=m.Files.Length)throw new InvalidDataException("Exactly the fixed manifest payload files required");
                var allowed=new HashSet<string>(m.Files,StringComparer.Ordinal);
                var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long total=0;
                foreach(var e in archive.Entries) {
                    if(!allowed.Contains(e.FullName) || !names.Add(e.FullName))throw new InvalidDataException("Archive name/alias/traversal rejected");
                    int unixType=(e.ExternalAttributes>>16)&0xF000;
                    if((unixType!=0 && unixType!=0x8000) || (e.ExternalAttributes&0x410)!=0)throw new InvalidDataException("Archive links/reparse/directories rejected");
                    long expected=m.FileSize(e.FullName);
                    if(e.Length!=expected || e.Length>Manifest.MaxExpanded || e.Length<1)throw new InvalidDataException("Archive size mismatch");
                    total+=e.Length;if(total>Manifest.MaxExpanded)throw new InvalidDataException("Expanded size exceeded");
                }
                foreach(var e in archive.Entries) {
                    string path=Paths.Child(destination,e.FullName);long totalRead=0;
                    using(var input=e.Open())using(var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                        byte[] buffer=new byte[32768];int n;while((n=input.Read(buffer,0,buffer.Length))>0) {totalRead+=n;if(totalRead>e.Length)throw new InvalidDataException("Decompression limit");output.Write(buffer,0,n);}output.Flush(true);
                    }
                    if(totalRead!=e.Length)throw new InvalidDataException("Truncated archive");
                    VerifyFile(path,e.Length,m.FileHash(e.FullName));
                }
            }
        }
        public void Rollback() {using(Acquire()) {
            var s=State();if(s==null || s.Previous=="")throw new InvalidOperationException("No known-good previous version");
            VerifyInstalled(s.Previous);string current=s.Current;s.Current=s.Previous;s.Previous=current;WriteState(s);
        }}
        public bool RealOffline; // Local opt-in only. Never controlled by the manifest.
        public bool QaAutoQuit; // Harness-only fixed engine flag; no manifest/launcher argument forwarding.
        public int? LastGameExitCode {get;private set;}
        public string LastGameCaptureDirectory {get;private set;}
        public void Play() {using(Acquire()) {
            var s=State();if(s==null)throw new InvalidOperationException("Install a DEV build first");VerifyInstalled(s.Current);
            var manifest=VerifyInstalled(s.Current);if(manifest.CompleteExport && !RealOffline)throw new InvalidOperationException("Real export requires local --dev-real-offline opt-in");
            string dir=P("versions\\"+s.Current);string exe=Paths.Child(dir,"FRAIHA.exe"),pck=Paths.Child(dir,"FRAIHA.pck");
            // Keep payload and operation handles while the game runs. No feed-supplied arguments.
            using(var exeHandle=new FileStream(exe,FileMode.Open,FileAccess.Read,FileShare.Read))using(var pckHandle=new FileStream(pck,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                var start=new ProcessStartInfo(exe){WorkingDirectory=dir,UseShellExecute=false,Arguments=""};
                if(RealOffline){
                    if(Root.Length>110)throw new InvalidOperationException("Reviewed historical export requires DEV root at most 110 characters for its shader cache");
                    if(!manifest.CompleteExport)throw new InvalidOperationException("Real offline mode refuses two-file fixtures");
                    if(manifest.ExeHash!="3bba9f68131498157e02ec44c296f996dd0a4d64c8fdb582d2794bd59feb4465" || (manifest.PckHash!="351a00c43297bf3feaad8cab7e28ea2974e7238589d050db09b8eb8018c3733c" && manifest.PckHash!="011137a3d88709cf5f2ab128648ebe5c325783824160939904b1860f74ab5433") || manifest.CfgHash!="ffaee9060a72096d914fc15346a3021d316c2ace6e9f36b780c956c7d325606e")throw new InvalidOperationException("Export has no reviewed DEV offline startup profile");
                    // Four-file v2 is homologated only for the inventoried historical V029/V030 exports.
                    // Their endpoint resolver honors this final local environment override.
                    string profile=P("userdata"),cache=P("userdata\\cache"),temp=P("userdata\\temp");
                    Paths.ReviewedProfile(profile);
                    Directory.CreateDirectory(profile);Directory.CreateDirectory(cache);Directory.CreateDirectory(temp);
                    start.EnvironmentVariables["APPDATA"]=profile;start.EnvironmentVariables["LOCALAPPDATA"]=cache;
                    start.EnvironmentVariables["TEMP"]=temp;start.EnvironmentVariables["TMP"]=temp;
                    start.EnvironmentVariables["FRAIHA_SERVER_URL"]="";start.EnvironmentVariables["FRAIHA_SUPABASE_URL"]="";start.EnvironmentVariables["FRAIHA_SUPABASE_KEY"]="";
                    if(QaAutoQuit){LastGameCaptureDirectory=P("qa-frames\\"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(LastGameCaptureDirectory);start.Arguments="--quit-after 12 --fixed-fps 1 --windowed --resolution 1280x720 --write-movie \""+Paths.Child(LastGameCaptureDirectory,"game.png")+"\"";}
                }
                LastGameExitCode=null;using(var process=Process.Start(start)){process.WaitForExit();LastGameExitCode=process.ExitCode;if(process.ExitCode!=0)throw new IOException("Game exited with code "+process.ExitCode);}
            }
        }}
    }
}
