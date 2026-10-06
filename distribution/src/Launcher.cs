using System;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Fraiha.Distribution {
    public sealed class LauncherForm:Form {
        readonly Updater updater; Manifest available;
        readonly TextBox feed=new TextBox(),notes=new TextBox();readonly Label installed=new Label(),offered=new Label(),status=new Label();readonly ProgressBar progress=new ProgressBar();
        readonly Button check=new Button(),update=new Button(),play=new Button(),rollback=new Button();bool busy;
        public LauncherForm(string root,bool autoStart=false,string autoFeed=null,bool realOffline=false) {
            updater=new Updater(root){RealOffline=realOffline};Text=realOffline?"FRAIHA — Launcher DEV (real offline export)":"FRAIHA — Launcher DEV (mock opt-in)";ClientSize=new Size(760,510);MinimumSize=new Size(700,520);StartPosition=FormStartPosition.CenterScreen;
            Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(20,35,27);ForeColor=Color.WhiteSmoke;
            var title=new Label{Text="FRAIHA  |  Windows Site  |  DEV",Location=new Point(22,18),Size=new Size(700,36),Font=new Font("Segoe UI",17,FontStyle.Bold)};Controls.Add(title);
            var path=new Label{Text="Local DEV path: "+root,Location=new Point(22,62),Size=new Size(710,48)};Controls.Add(path);
            installed.Location=new Point(22,113);installed.Size=new Size(690,24);offered.Location=new Point(22,141);offered.Size=new Size(690,24);Controls.Add(installed);Controls.Add(offered);
            feed.Text="http://127.0.0.1:8765/manifest.json";feed.Location=new Point(22,177);feed.Size=new Size(710,28);Controls.Add(feed);
            if(autoFeed!=null)feed.Text=autoFeed;
            check.Text="Check / Retry";update.Text="Download / Update";play.Text="PLAY";rollback.Text="Rollback";
            Button[] buttons={check,update,play,rollback};for(int i=0;i<buttons.Length;i++){buttons[i].Location=new Point(22+i*179,219);buttons[i].Size=new Size(167,37);buttons[i].ForeColor=Color.Black;buttons[i].BackColor=Color.FromArgb(240,222,173);buttons[i].UseVisualStyleBackColor=false;Controls.Add(buttons[i]);}
            progress.Location=new Point(22,271);progress.Size=new Size(710,22);Controls.Add(progress);
            status.Location=new Point(22,304);status.Size=new Size(710,45);Controls.Add(status);
            notes.Location=new Point(22,357);notes.Size=new Size(710,128);notes.Multiline=true;notes.ReadOnly=true;notes.ScrollBars=ScrollBars.Vertical;notes.Text="DEV only. The local feed contains a test stub, not a Godot game export. Production update remains blocked until signed-manifest trust is implemented.";Controls.Add(notes);
            if(realOffline)notes.Text="DEV offline only. Reviewed historical V029/V030 FRAIHA exports; isolated userdata and disabled online endpoint. Distribution build numbers are DEV metadata. Production trust remains blocked.";
            check.Click+=delegate {string url=feed.Text;Run(delegate{available=updater.Download.Check(url,"DEV");available.RequireDevTrust();Ui(delegate{offered.Text="Available: "+available.Release.Version+" / build "+available.Release.Build;notes.Text=available.Notes;});});};
            update.Click+=delegate {Run(delegate{if(available==null)throw new InvalidOperationException("Check the DEV feed first");updater.Install(available,delegate(long done,long total){Ui(delegate{progress.Value=total<=0?0:(int)Math.Min(100,done*100/total);status.Text="Downloaded "+done+" / "+total+" bytes";});});});};
            play.Click+=delegate{Run(delegate{Ui(delegate{status.Text="Game running; update locked until exit";});updater.Play();});};
            rollback.Click+=delegate{Run(delegate{updater.Rollback();});};
            FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy)e.Cancel=true;};RefreshInstalled();
            if(autoStart)Shown+=delegate {string url=feed.Text;Run(delegate {new LauncherFlow(updater).CheckUpdatePlay(url,
                delegate(long done,long total){Ui(delegate{progress.Value=(int)Math.Min(100,done*100/total);status.Text="Downloaded "+done+" / "+total+" bytes";});},
                delegate(Manifest m){available=m;Ui(delegate{offered.Text="Available: "+m.Release.Version+" / build "+m.Release.Build;notes.Text=m.Notes;});},
                delegate{Ui(delegate{status.Text="Game running; update locked until exit";});});});};
        }
        void Ui(Action a) {if(!IsDisposed)Invoke(a);}
        void RefreshInstalled() {try{var m=updater.Installed();installed.Text=m==null?"Installed: none": "Installed: "+m.Release.Version+" / build "+m.Release.Build;}catch(Exception e){installed.Text="Installed state error: "+e.Message;}}
        void Run(Action action) {
            if(busy)return;busy=true;check.Enabled=update.Enabled=play.Enabled=rollback.Enabled=feed.Enabled=false;progress.Value=0;status.Text="Working…";
            Task.Factory.StartNew(delegate{string result="Completed";try{action();}catch(Exception e){result="Error: "+e.Message+" — Check / Retry";}Ui(delegate{busy=false;status.Text=result;check.Enabled=update.Enabled=play.Enabled=rollback.Enabled=feed.Enabled=true;RefreshInstalled();});});
        }
    }
    public static class Launcher {
        [STAThread]public static int Main(string[] args) {
            Paths.InitializeRuntime();
            if((args.Length!=1 && args.Length!=2) || (args[0]!="--dev-mock" && args[0]!="--dev-real-offline") || (args.Length==2 && args[1]!="--auto-play")) {MessageBox.Show("Requires --dev-mock or --dev-real-offline; optional --auto-play checks, updates and launches. Production blocked pending signed-manifest trust.","FRAIHA");return 2;}
            bool real=args[0]=="--dev-real-offline";
            try{Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new LauncherForm(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,real?"dev-real-install":"dev-install"),args.Length==2,null,real));return 0;}
            catch(Exception e){MessageBox.Show(e.Message,"FRAIHA DEV error");return 1;}
        }
    }
}
