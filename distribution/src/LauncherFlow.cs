using System;
using System.IO;

namespace Fraiha.Distribution {
    public sealed class LauncherFlow {
        readonly Updater updater;
        public LauncherFlow(Updater updater) {this.updater=updater;}
        public void CheckUpdatePlay(string feed,Action<long,long> progress,Action<Manifest> offered,Action startingGame) {
            var available=updater.Download.Check(feed,"DEV");available.RequireDevTrust();if(offered!=null)offered(available);
            var installed=updater.Installed();
            if(installed==null)updater.Install(available,progress);
            else if(installed.Release.Id==available.Release.Id) {
                if(installed.Hash!=available.Hash || installed.CompleteExport!=available.CompleteExport || installed.ExeHash!=available.ExeHash || installed.PckHash!=available.PckHash || installed.ExeSize!=available.ExeSize || installed.PckSize!=available.PckSize || installed.CfgHash!=available.CfgHash || installed.ReadmeHash!=available.ReadmeHash || installed.CfgSize!=available.CfgSize || installed.ReadmeSize!=available.ReadmeSize || installed.Release.Protocol!=available.Release.Protocol || installed.Release.Rules!=available.Release.Rules || installed.Release.Channel!=available.Release.Channel || installed.Release.Platform!=available.Release.Platform)throw new InvalidDataException("Same build has conflicting content/identity");
            } else {Release.RequireUpgrade(installed.Release,available.Release);updater.Install(available,progress);}
            if(startingGame!=null)startingGame();updater.Play();
            // Any exception from check/download/hash/install skips PLAY; never launch stale state on error.
        }
    }
}
