using System;
using System.IO;
using System.Threading;
// Test executable only, never a Godot export or production game.
public static class GameStub {
    public static void Main() {File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"stub-launched.txt"),"DEV test stub, not Godot");Thread.Sleep(1500);}
}
