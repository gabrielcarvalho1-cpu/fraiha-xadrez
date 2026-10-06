using System;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace Fraiha.Distribution {
    public static class PackageTool {
        public static Manifest Package(string versionFile,string source,string output,string packageUrl,string notes) {
            var release=Release.Read(Json.ReadFile(versionFile));if(release.Platform!="windows_site")throw new InvalidDataException("Only Windows site ZIP packaging implemented");
            Paths.NoReparse(source);Paths.NoReparse(output);
            string[] files=Directory.GetFileSystemEntries(source);
            bool complete=files.Length==4 && File.Exists(Path.Combine(source,"online.cfg")) && File.Exists(Path.Combine(source,"LEIA-ME.txt"));
            if((files.Length!=2 && !complete) || !File.Exists(Path.Combine(source,"FRAIHA.exe")) || !File.Exists(Path.Combine(source,"FRAIHA.pck")))throw new InvalidDataException("Source must contain exactly the fixed two-file fixture or complete four-file export");
            foreach(string f in files)Paths.NoReparse(f);
            Directory.CreateDirectory(output); string zip=Path.Combine(output,"fraiha-"+release.Id+".zip");
            string manifestFile=Path.Combine(output,"manifest.json");
            if(File.Exists(zip) || File.Exists(manifestFile))throw new IOException("Output already exists; choose a new directory");
            string exe=Path.Combine(source,"FRAIHA.exe"),pck=Path.Combine(source,"FRAIHA.pck");
            long exeSize=new FileInfo(exe).Length,pckSize=new FileInfo(pck).Length;
            if(exeSize<1 || pckSize<1 || exeSize+pckSize>Manifest.MaxExpanded)throw new InvalidDataException("Export size limits");
            // Validate URL/notes before writing any package.
            var m=new Manifest{Release=release,Url=Manifest.SafeUrl(packageUrl,release.Channel),Size=1,Hash=new string('0',64),ExeSize=exeSize,ExeHash=Manifest.Sha(exe),PckSize=pckSize,PckHash=Manifest.Sha(pck),Notes=notes,Date=DateTime.UtcNow.ToString("yyyy-MM-dd"),Mandatory=false};
            m.CompleteExport=complete;if(complete){string cfg=Path.Combine(source,"online.cfg"),readme=Path.Combine(source,"LEIA-ME.txt");m.CfgSize=new FileInfo(cfg).Length;m.CfgHash=Manifest.Sha(cfg);m.ReadmeSize=new FileInfo(readme).Length;m.ReadmeHash=Manifest.Sha(readme);}
            Manifest.Read(Json.Write(m.Data()));
            using(var archive=ZipFile.Open(zip,ZipArchiveMode.Create)) {
                foreach(string name in m.Files)archive.CreateEntryFromFile(Path.Combine(source,name),name,CompressionLevel.Optimal);
            }
            m.Size=new FileInfo(zip).Length;m.Hash=Manifest.Sha(zip);Manifest.Read(Json.Write(m.Data()));
            File.WriteAllText(manifestFile,Json.Write(m.Data()),new UTF8Encoding(false));
            // A package's manifest is its metadata; build does not imply signing or publication.
            return m;
        }
        public static int Main(string[] args) {
            Paths.InitializeRuntime();
            try {
                if(args.Length==2 && args[0]=="validate-version") {var r=Release.Read(Json.ReadFile(args[1]));Console.WriteLine(r.Channel+" "+r.Platform+" "+r.Id);return 0;}
                if(args.Length==7 && args[0]=="package") {
                    if(args[6]!="--dev-only")throw new InvalidOperationException("DEV opt-in required");
                    var r=Release.Read(Json.ReadFile(args[1]));if(r.Channel!="DEV")throw new InvalidOperationException("CLI packaging is DEV-only");
                    var u=Manifest.SafeUrl(args[4],"DEV");if(u.Scheme!="http")throw new InvalidOperationException("DEV packaging requires loopback mock URL");
                    var m=Package(args[1],args[2],args[3],args[4],args[5]);m.RequireDevTrust();Console.WriteLine(m.Release.Id+" SHA256 "+m.Hash);return 0;
                }
                Console.Error.WriteLine("validate-version <version.json> | package <version.json> <two-file-export-dir> <output-dir> <package-url> <notes> --dev-only");return 2;
            }catch(Exception e){Console.Error.WriteLine(e.Message);return 1;}
        }
    }
}
