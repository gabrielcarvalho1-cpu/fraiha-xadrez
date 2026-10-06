using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace Fraiha.Distribution {
    // Deliberately flat JSON: no nested commands, paths, arbitrary files or executable names.
    public static class Json {
        public static Dictionary<string, object> Read(string text) {
            if (text == null || Encoding.UTF8.GetByteCount(text) > 32768) throw new InvalidDataException("JSON size limit");
            int p = 0; var d = new Dictionary<string, object>(StringComparer.Ordinal);
            White(text, ref p); Take(text, ref p, '{'); White(text, ref p);
            if (p < text.Length && text[p] == '}') { p++; } else {
                while (true) {
                    string k = String(text, ref p); White(text, ref p); Take(text, ref p, ':'); White(text, ref p);
                    object v;
                    if (p < text.Length && text[p] == '"') v = String(text, ref p);
                    else if (text.Substring(p).StartsWith("true", StringComparison.Ordinal)) { p += 4; v = true; }
                    else if (text.Substring(p).StartsWith("false", StringComparison.Ordinal)) { p += 5; v = false; }
                    else {
                        int start = p; while (p < text.Length && text[p] >= '0' && text[p] <= '9') p++;
                        string number = text.Substring(start, p-start); long n;
                        if (!Regex.IsMatch(number, "^(0|[1-9][0-9]*)$") || !long.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out n)) throw new InvalidDataException("Expected unsigned integer");
                        v = n;
                    }
                    if (d.ContainsKey(k)) throw new InvalidDataException("Duplicate JSON key"); d.Add(k, v);
                    White(text, ref p); if (p < text.Length && text[p] == '}') { p++; break; }
                    Take(text, ref p, ','); White(text, ref p);
                }
            }
            White(text, ref p); if (p != text.Length) throw new InvalidDataException("Trailing JSON"); return d;
        }
        static void White(string s, ref int p) { while (p<s.Length && (s[p]==' ' || s[p]=='\t' || s[p]=='\r' || s[p]=='\n')) p++; }
        static void Take(string s, ref int p, char c) { if (p>=s.Length || s[p++]!=c) throw new InvalidDataException("Malformed JSON"); }
        static string String(string s, ref int p) {
            int start=p; Take(s, ref p, '"'); bool ended=false;
            while (p<s.Length) {
                char c=s[p++]; if(c=='"') { ended=true; break; }
                if(c<32) throw new InvalidDataException("JSON control character");
                if(c=='\\') {
                    if(p>=s.Length) throw new InvalidDataException("JSON escape"); char e=s[p++];
                    if(e=='u') { for(int i=0;i<4;i++) { if(p>=s.Length || !Uri.IsHexDigit(s[p++])) throw new InvalidDataException("JSON unicode"); } }
                    else if("\"\\/bfnrt".IndexOf(e)<0) throw new InvalidDataException("JSON escape");
                }
            }
            if(!ended) throw new InvalidDataException("Unterminated JSON string");
            return new JavaScriptSerializer().Deserialize<string>(s.Substring(start,p-start));
        }
        public static string Write(Dictionary<string,object> d) { return new JavaScriptSerializer().Serialize(d); }
        public static string Text(Dictionary<string,object> d,string k) { if(!d.ContainsKey(k) || !(d[k] is string)) throw new InvalidDataException("Expected string: "+k); return (string)d[k]; }
        public static long Number(Dictionary<string,object> d,string k,long max) { if(!d.ContainsKey(k) || !(d[k] is long) || (long)d[k]>max) throw new InvalidDataException("Expected bounded integer: "+k); return (long)d[k]; }
        public static bool Bool(Dictionary<string,object> d,string k) { if(!d.ContainsKey(k) || !(d[k] is bool)) throw new InvalidDataException("Expected boolean: "+k); return (bool)d[k]; }
        public static void Keys(Dictionary<string,object> d,string list) {
            var keys=new HashSet<string>(list.Split(','),StringComparer.Ordinal);
            if(d.Count!=keys.Count) throw new InvalidDataException("Missing/extra fields");
            foreach(string k in d.Keys) if(!keys.Contains(k)) throw new InvalidDataException("Unknown field: "+k);
        }
        public static string ReadFile(string file) { using(var f=File.OpenRead(file)) { if(f.Length>32768) throw new InvalidDataException("JSON file size"); using(var r=new StreamReader(f,new UTF8Encoding(false,true),true)) return r.ReadToEnd(); } }
    }
    public class Release {
        public const string Fields="schema_version,game_version,build_number,protocol_version,rules_version,release_channel,platform,development_only";
        public string Version,Channel,Platform; public long Build,Protocol,Rules; public bool DevOnly;
        public static readonly string[] Platforms={"web","windows_site","windows_steam","android","ios"};
        public static Release Read(string text) { var d=Json.Read(text); Json.Keys(d,Fields); return From(d); }
        public static Release From(Dictionary<string,object> d) {
            if(Json.Number(d,"schema_version",1)!=1) throw new InvalidDataException("Unknown schema");
            var r=new Release {Version=Json.Text(d,"game_version"),Build=Json.Number(d,"build_number",2100000000),Protocol=Json.Number(d,"protocol_version",int.MaxValue),Rules=Json.Number(d,"rules_version",int.MaxValue),Channel=Json.Text(d,"release_channel"),Platform=Json.Text(d,"platform"),DevOnly=Json.Bool(d,"development_only")};
            VersionParts(r.Version); if(r.Build<1) throw new InvalidDataException("Build must be positive");
            if(r.Channel!="DEV" && r.Channel!="BETA" && r.Channel!="STABLE") throw new InvalidDataException("Unknown channel");
            if(Array.IndexOf(Platforms,r.Platform)<0) throw new InvalidDataException("Unknown platform");
            if(r.Channel!="DEV" && (r.DevOnly || r.Protocol==0 || r.Rules==0 || r.Version=="0.0.0")) throw new InvalidDataException("Unassigned production versions");
            if(r.Channel=="DEV" && !r.DevOnly) throw new InvalidDataException("DEV must be explicit"); return r;
        }
        static int[] VersionParts(string s) {
            if(s==null || !Regex.IsMatch(s,@"^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$")) throw new InvalidDataException("Invalid game version");
            string[] p=s.Split('.'); return new[]{int.Parse(p[0]),int.Parse(p[1]),int.Parse(p[2])};
        }
        public static int CompareVersion(string a,string b) { int[] x=VersionParts(a),y=VersionParts(b); for(int i=0;i<3;i++) { int c=x[i].CompareTo(y[i]); if(c!=0)return c; } return 0; }
        public string Id {get {return Version+"-"+Build.ToString(CultureInfo.InvariantCulture);}}
        public Dictionary<string,object> Data() { return new Dictionary<string,object>{{"schema_version",1L},{"game_version",Version},{"build_number",Build},{"protocol_version",Protocol},{"rules_version",Rules},{"release_channel",Channel},{"platform",Platform},{"development_only",DevOnly}}; }
        public static void RequireUpgrade(Release installed,Release offered) {
            if(installed.Channel!=offered.Channel || installed.Platform!=offered.Platform) throw new InvalidDataException("Channel/platform mismatch");
            if(offered.Build<=installed.Build || CompareVersion(offered.Version,installed.Version)<0) throw new InvalidDataException("Same build or downgrade rejected");
        }
    }
    public enum Compatibility { COMPATIBLE, UPDATE_REQUIRED, INCOMPATIBLE_PROTOCOL, MAINTENANCE }
    public static class CompatibilityContract {
        // No backend integration. Distribution identity is not a trusted authentication claim.
        public static Compatibility Evaluate(Release client,long protocol,long rules,long minimumBuild,bool maintenance) {
            if(protocol<0 || rules<0 || minimumBuild<1) throw new ArgumentOutOfRangeException();
            if(maintenance)return Compatibility.MAINTENANCE;
            if(client.Protocol!=protocol || client.Rules!=rules)return Compatibility.INCOMPATIBLE_PROTOCOL;
            return client.Build<minimumBuild?Compatibility.UPDATE_REQUIRED:Compatibility.COMPATIBLE;
        }
    }
    public class Manifest {
        public const long MaxPackage=536870912,MaxExpanded=1073741824;
        public const string Extra=",format,package_url,package_size,sha256,exe_size,exe_sha256,pck_size,pck_sha256,release_notes,mandatory,date";
        public Release Release; public Uri Url; public long Size,ExeSize,PckSize,CfgSize,ReadmeSize; public string Hash,ExeHash,PckHash,CfgHash,ReadmeHash,Notes,Date; public bool Mandatory,CompleteExport;
        public const string CompleteExtra=",cfg_size,cfg_sha256,readme_size,readme_sha256";
        public string[] Files {get{return CompleteExport?new[]{"FRAIHA.exe","FRAIHA.pck","online.cfg","LEIA-ME.txt"}:new[]{"FRAIHA.exe","FRAIHA.pck"};}}
        public long FileSize(string name) {switch(name){case "FRAIHA.exe":return ExeSize;case "FRAIHA.pck":return PckSize;case "online.cfg":return CfgSize;case "LEIA-ME.txt":return ReadmeSize;default:throw new InvalidDataException("Unknown payload");}}
        public string FileHash(string name) {switch(name){case "FRAIHA.exe":return ExeHash;case "FRAIHA.pck":return PckHash;case "online.cfg":return CfgHash;case "LEIA-ME.txt":return ReadmeHash;default:throw new InvalidDataException("Unknown payload");}}
        public static Manifest Read(string text) {
            var d=Json.Read(text);string format=Json.Text(d,"format");bool complete=format=="fraiha-flat-zip-v2";Json.Keys(d,Release.Fields+Extra+(complete?CompleteExtra:"")); var r=Release.From(d);
            if(r.Platform!="windows_site" || (!complete && format!="fraiha-flat-zip-v1"))throw new InvalidDataException("Not a Windows site package");
            var m=new Manifest {Release=r,Url=SafeUrl(Json.Text(d,"package_url"),r.Channel),Size=Json.Number(d,"package_size",MaxPackage),ExeSize=Json.Number(d,"exe_size",MaxExpanded),PckSize=Json.Number(d,"pck_size",MaxExpanded),Hash=HashField(d,"sha256"),ExeHash=HashField(d,"exe_sha256"),PckHash=HashField(d,"pck_sha256"),Notes=Json.Text(d,"release_notes"),Date=Json.Text(d,"date"),Mandatory=Json.Bool(d,"mandatory")};
            m.CompleteExport=complete;if(complete){m.CfgSize=Json.Number(d,"cfg_size",32768);m.CfgHash=HashField(d,"cfg_sha256");m.ReadmeSize=Json.Number(d,"readme_size",1048576);m.ReadmeHash=HashField(d,"readme_sha256");if(m.CfgSize<1 || m.ReadmeSize<1 || m.ExeSize+m.PckSize+m.CfgSize+m.ReadmeSize>MaxExpanded)throw new InvalidDataException("Complete export limits");}
            DateTime date; if(!DateTime.TryParseExact(m.Date,"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out date))throw new InvalidDataException("Invalid date");
            if(m.Size<1 || m.ExeSize<1 || m.PckSize<1 || m.ExeSize+m.PckSize>MaxExpanded || m.Notes.Length>4096)throw new InvalidDataException("Package limits");
            foreach(char c in m.Notes) if(char.IsControl(c) && c!='\r' && c!='\n' && c!='\t')throw new InvalidDataException("Notes controls"); return m;
        }
        static string HashField(Dictionary<string,object>d,string k) { string s=Json.Text(d,k); if(!Regex.IsMatch(s,"^[0-9a-f]{64}$"))throw new InvalidDataException("SHA256 format"); return s; }
        public static Uri SafeUrl(string raw,string channel) {
            Uri u;
            // Reject ambiguous/canonicalized forms before Uri normalizes dot segments.
            if(raw==null || raw.Length>2048 || Regex.IsMatch(raw,@"\s") || raw.Contains("\\") || raw.Contains("%") || raw.Contains("..") || !Uri.TryCreate(raw,UriKind.Absolute,out u) || !string.IsNullOrEmpty(u.UserInfo) || !string.IsNullOrEmpty(u.Fragment) || !string.IsNullOrEmpty(u.Query))throw new InvalidDataException("Unsafe URL");
            if(u.Scheme=="https")return u;
            IPAddress ip; if(channel=="DEV" && u.Scheme=="http" && Regex.IsMatch(raw,@"^http://(127\.0\.0\.1|\[::1\])(:[0-9]{1,5})?/") && IPAddress.TryParse(u.Host.Trim('[',']'),out ip) && IPAddress.IsLoopback(ip))return u;
            throw new InvalidDataException("HTTPS required; HTTP only literal DEV loopback");
        }
        public Dictionary<string,object> Data() { var d=Release.Data(); d.Add("format",CompleteExport?"fraiha-flat-zip-v2":"fraiha-flat-zip-v1");d.Add("package_url",Url.OriginalString);d.Add("package_size",Size);d.Add("sha256",Hash);d.Add("exe_size",ExeSize);d.Add("exe_sha256",ExeHash);d.Add("pck_size",PckSize);d.Add("pck_sha256",PckHash);if(CompleteExport){d.Add("cfg_size",CfgSize);d.Add("cfg_sha256",CfgHash);d.Add("readme_size",ReadmeSize);d.Add("readme_sha256",ReadmeHash);}d.Add("release_notes",Notes);d.Add("mandatory",Mandatory);d.Add("date",Date);return d; }
        public static string Sha(string file) { using(var s=File.OpenRead(file))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","").ToLowerInvariant(); }
        public void RequireDevTrust() {
            if(Release.Channel!="DEV" || !Release.DevOnly || Url.Scheme!="http")throw new InvalidOperationException("Production signature/trust anchor not implemented: update blocked");
            SafeUrl(Url.OriginalString,"DEV");
        }
    }
}
