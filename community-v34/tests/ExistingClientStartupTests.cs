using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace DragonLauncher {
internal static class ExistingClientStartupTests {
    static int checks;
    static void Check(bool value,string message){checks++;if(!value)throw new Exception(message);}
    sealed class Target {internal bool Current=true;}
    sealed class Fixture {
        internal long Now;
        internal int Finds,Activations,Inspections,Prompts,RunningChecks,Clears;
        internal Target Window=new Target();
        internal WarmHostState Host=WarmHostState.Managed;
        internal Func<int,Target> FindBehavior;
        internal Func<int,bool> RunningBehavior;
        internal Func<int,bool> RetryBehavior;
        internal Action<int> ActivationBehavior;
        internal Action InspectionBehavior;
        internal readonly List<string> Logs=new List<string>();
        internal readonly List<bool> PromptStillRunning=new List<bool>();
        internal readonly List<int> ActivationBudgets=new List<int>();
        internal WarmStartupHooks<Target> Hooks;
        internal Fixture(){
            Hooks=new WarmStartupHooks<Target>{
                Find=scope=>{Finds++;Now+=10;return FindBehavior==null?Window:FindBehavior(Finds);},
                IsCurrent=target=>target.Current,
                IsRunning=()=>{RunningChecks++;Now+=10;return RunningBehavior==null||RunningBehavior(RunningChecks);},
                Activate=budget=>{Activations++;ActivationBudgets.Add(budget);Now+=10;if(ActivationBehavior!=null)ActivationBehavior(budget);},
                InspectHost=target=>{Inspections++;Now+=10;if(InspectionBehavior!=null)InspectionBehavior();return Host;},
                AskRetry=still=>{Prompts++;PromptStillRunning.Add(still);Now+=12000;return RetryBehavior!=null&&RetryBehavior(Prompts);},
                Elapsed=()=>Now,Delay=ms=>Now+=ms,ClearUncommitted=()=>Clears++,
                Read=(read,budget)=>{var scope=new WarmObservation();try{return read(scope);}finally{scope.Close();}}
            };
        }
        internal WarmStartupResult<Target> Run(bool wallpaper=true){return ExistingClientStartup.Decide(wallpaper,Hooks,Logs.Add);}
    }
    static void DecisionCases(){
        var f=new Fixture();f.FindBehavior=n=>null;f.RunningBehavior=n=>false;
        var r=f.Run();Check(r.Decision==WarmStartupDecision.Cold&&r.Reason=="no-running","fresh absence permits cold despite stale replay hint");
        Check(f.Activations==0&&f.Clears==1&&f.Prompts==0,"cold only clears uncommitted cache without app activation");
        f=new Fixture();r=f.Run();Check(r.Decision==WarmStartupDecision.Replay&&r.Reason=="existing-window","existing managed window replays");
        Check(f.Activations==0&&f.Inspections==1&&f.Prompts==0,"managed replay does not restart or prompt");
        foreach(var state in new[]{WarmHostState.Disabled,WarmHostState.Paused,WarmHostState.Faulted}){
            f=new Fixture{Host=state};r=f.Run();Check(r.Decision==WarmStartupDecision.Replay&&r.HostState==state,"authenticated managed state retained "+state);
            Check(f.Activations==0&&f.Prompts==0,"managed user intent never forces restart "+state);
        }
        f=new Fixture();f.FindBehavior=n=>n<4?null:f.Window;r=f.Run();
        Check(r.Decision==WarmStartupDecision.Replay&&r.Reason=="window-recovered","background/orphan hint can recover a verified window");
        Check(f.Activations==1&&f.RunningChecks==1&&f.Finds==4,"recovery sends one activation and only observes thereafter");
        Check(f.ActivationBudgets[0]<=4000&&f.Now<=8000,"activation and observations fit original deadline");
        f=new Fixture();f.FindBehavior=n=>null;r=f.Run();
        Check(r.Decision==WarmStartupDecision.Unavailable&&r.Reason=="window-timeout","persistent background cannot become cold fallback");
        Check(f.Activations==1&&f.Clears==0&&f.Prompts==0&&f.Now<=8000,"no-window deadline neither restarts nor prompts a hidden cover");
        f=new Fixture();f.FindBehavior=n=>null;f.ActivationBehavior=budget=>{throw new TimeoutException();};r=f.Run();
        Check(r.Reason=="activation-timeout"&&r.Decision==WarmStartupDecision.Unavailable,"activation uncertainty is terminal");
        Check(f.Activations==1&&f.Finds==1&&f.Clears==0&&f.Prompts==0,"timed-out activation gets no second request or cold fallback");
        f=new Fixture();f.FindBehavior=n=>null;f.ActivationBehavior=budget=>{throw new InvalidOperationException("private error must not log");};r=f.Run();
        Check(r.Reason=="activation-failed"&&f.Finds==1&&f.Prompts==0,"activation error remains terminal even if process may have opened");
        f=new Fixture();f.Hooks.Read=(read,budget)=>{throw new TimeoutException();};r=f.Run();
        Check(r.Reason=="observation-timeout"&&f.Activations==0&&f.Clears==0,"read timeout cannot authorize any activation");
        f=new Fixture();f.FindBehavior=n=>{f.Now=8000;return f.Window;};r=f.Run();
        Check(r.Reason=="observation-timeout"&&f.Inspections==0,"late returned candidate does not bypass original deadline");
        f=new Fixture();f.FindBehavior=n=>null;f.RunningBehavior=n=>{throw new InvalidOperationException();};r=f.Run();
        Check(r.Reason=="identity-unavailable"&&f.Activations==0,"unverifiable official state fails closed");
        f=new Fixture();f.Window.Current=false;r=f.Run();
        Check(r.Reason=="target-ended"&&f.Inspections==0&&f.Finds==1,"ended pin is not replaced before host observation");
        f=new Fixture();f.InspectionBehavior=()=>f.Window.Current=false;r=f.Run();
        Check(r.Reason=="target-ended"&&f.Finds==1&&f.Activations==0,"ended pin after host observation is not retargeted");
        f=new Fixture{Host=WarmHostState.Unavailable};r=f.Run();
        Check(r.Decision==WarmStartupDecision.Cancelled&&r.Reason=="user-cancelled","unhosted ordinary client never silently succeeds");
        Check(f.Prompts==1&&f.Activations==0&&f.Clears==0,"cancel retains existing client without another launch");
        f=new Fixture{Host=WarmHostState.Unverified};f.RetryBehavior=n=>true;f.RunningBehavior=n=>false;r=f.Run();
        Check(r.Decision==WarmStartupDecision.Cold&&r.Reason=="manual-retry-cold","explicit retry with fresh verified absence permits cold");
        Check(f.Clears==1&&f.Activations==0&&f.Now>8000,"human prompt time is not an automatic loading timeout");
        f=new Fixture{Host=WarmHostState.Unavailable};f.RetryBehavior=n=>n<=2;f.RunningBehavior=n=>true;r=f.Run();
        Check(r.Decision==WarmStartupDecision.Cancelled&&f.Prompts==3&&f.RunningChecks==2,"still-running retries remain explanatory until cancel");
        Check(!f.PromptStillRunning[0]&&f.PromptStillRunning[1]&&f.PromptStillRunning[2],"retry explains background process remains");
        Check(f.Activations==0&&f.Finds==1&&f.Clears==0,"manual retry does not reactivate or reselect visible target");
        f=new Fixture{Host=WarmHostState.Unavailable};f.FindBehavior=n=>n==1?null:f.Window;f.RetryBehavior=n=>true;f.RunningBehavior=n=>n==1;r=f.Run();
        Check(r.Decision==WarmStartupDecision.Cold&&r.ActivationCount==1&&f.Activations==1,"completed wake then explicit full-exit retry may cold launch once");
        f=new Fixture{Host=WarmHostState.Unavailable};r=f.Run(false);
        Check(r.Decision==WarmStartupDecision.Replay&&r.Reason=="animation-only"&&r.HostState==WarmHostState.AnimationOnly,"explicit wallpaper-off configuration remains animation-only");
        Check(f.Inspections==0&&f.Prompts==0,"requested animation-only avoids host mutation or quit prompt");
        f=new Fixture{Host=WarmHostState.Unavailable};f.RetryBehavior=n=>true;f.RunningBehavior=n=>{throw new TimeoutException();};r=f.Run();
        Check(r.Decision==WarmStartupDecision.Unavailable&&r.Reason=="observation-timeout"&&f.Clears==0,"manual retry requires affirmative absence, not read failure");
        Check(ExistingClientStartup.ShouldCoordinate(new Settings{AppId=BridgeClientIdentity.OfficialAppId},false),"official entry reclassifies even when parent replay flag is false");
        Check(!ExistingClientStartup.ShouldCoordinate(new Settings{AppId=BridgeClientIdentity.OfficialAppId},true),"preview never coordinates real app");
        Check(!ExistingClientStartup.ShouldCoordinate(new Settings{AppId=BridgeClientIdentity.OfficialAppId,Exe="fixture.exe"},false),"custom executable keeps existing route");
        Check(!ExistingClientStartup.ShouldCoordinate(new Settings{AppId="Other.App!App"},false),"nonofficial app keeps existing route");
        // The coordinator deliberately does not start Host. Its cold result is
        // a route decision; existing Host performs both locked running checks.
        f=new Fixture();f.FindBehavior=n=>null;f.RunningBehavior=n=>false;r=f.Run();
        Check(r.Target==null&&f.Activations==0&&f.RunningChecks==1,"cold race remains delegated to existing locked host guard");
    }
    static void HostStatusCases(){
        Check(ExistingClientStartup.ClassifyManagedHost(new BridgeStatus{MediaCode=6,Disabled=true,DesiredMode="disabled"})==WarmHostState.Disabled,"actual processed user-disable code6 is disabled, not fault");
        Check(ExistingClientStartup.ClassifyManagedHost(new BridgeStatus{MediaCode=166,Disabled=true,DesiredMode="enabled"})==WarmHostState.Faulted,"terminal host failure remains faulted");
        Check(ExistingClientStartup.ClassifyManagedHost(new BridgeStatus{MediaCode=5,DesiredMode="user-paused"})==WarmHostState.Paused,"actual user pause remains paused");
        Check(ExistingClientStartup.ClassifyManagedHost(new BridgeStatus{MediaCode=2,MemoryPressure=true,DesiredMode="enabled"})==WarmHostState.Managed,"resource suspension retains managed intent");
        Check(ExistingClientStartup.ClassifyManagedHost(new BridgeStatus{MediaCode=4,Ready=true})==WarmHostState.Managed,"managed readiness does not claim playback progress");
    }
    static void LateObservationCase(){
        using(var release=new ManualResetEvent(false))using(var finished=new ManualResetEvent(false)){
            var f=new Fixture();f.Hooks.Find=scope=>{try{release.WaitOne(2000);return f.Window;}finally{finished.Set();}};
            f.Hooks.Read=(read,budget)=>ExistingClientStartup.BoundedRead(read,Math.Min(40,budget));
            var clock=Stopwatch.StartNew();var result=f.Run();
            Check(result.Reason=="observation-timeout"&&clock.ElapsedMilliseconds<1000,"blocked read has a real caller bound");
            int logCount=f.Logs.Count;release.Set();Check(finished.WaitOne(1000),"late synthetic read released cooperatively");
            Check(f.Activations==0&&f.Clears==0&&f.Prompts==0&&f.Logs.Count==logCount,"late result never changes terminal decision or activates app");
        }
    }
    static void LateActivationCases(){
        foreach(bool fault in new[]{false,true}){
            using(var release=new ManualResetEvent(false))using(var finished=new ManualResetEvent(false)){
                var f=new Fixture();f.FindBehavior=n=>null;
                f.ActivationBehavior=budget=>AppActivation.OpenBoundedCore(()=>{
                    try{release.WaitOne(2000);if(fault)throw new InvalidOperationException("owned late activation fixture fault");return 123u;}
                    finally{finished.Set();}
                },40);
                var clock=Stopwatch.StartNew();var result=f.Run();
                Check(result.Decision==WarmStartupDecision.Unavailable&&result.Reason=="activation-timeout"&&clock.ElapsedMilliseconds<1000,"real bounded activation times out before late "+(fault?"fault":"success"));
                int logCount=f.Logs.Count;release.Set();Check(finished.WaitOne(1000),"owned late activation delegate finishes cooperatively");
                Check(f.Activations==1&&f.Finds==1&&f.Prompts==0&&f.Clears==0&&f.Logs.Count==logCount,"late activation outcome never authorizes another request or cold branch");
            }
        }
    }

    // Native checks run only on a newly created NON-INPUT desktop and use this
    // test executable as their app. No SwitchDesktop or official app launch.
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct StartInfo{public int Size;public string Reserved,Desktop,Title;public uint X,Y,XSize,YSize,XCount,YCount,Fill,Flags;public short Show,ReservedSize;public IntPtr ReservedBytes,Input,Output,Error;}
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo{public IntPtr Process,Thread;public uint Pid,Tid;}
    [StructLayout(LayoutKind.Sequential)] struct Message{public IntPtr Hwnd;public uint Code;public IntPtr WParam,LParam;public uint Time;public int X,Y;public uint Private;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string application,StringBuilder command,IntPtr processAttributes,IntPtr threadAttributes,bool inherit,uint flags,IntPtr environment,string directory,ref StartInfo startup,out ProcessInfo result);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateDesktop(string name,IntPtr device,IntPtr mode,uint flags,uint access,IntPtr attrs);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
    [DllImport("user32.dll")] static extern bool PeekMessage(out Message message,IntPtr window,uint first,uint last,uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref Message message);
    static Process StartPrivate(string desktop,string args){
        string executable=Assembly.GetExecutingAssembly().Location;var startup=new StartInfo{Size=Marshal.SizeOf(typeof(StartInfo)),Desktop=desktop,Flags=1,Show=0};ProcessInfo info;
        if(!CreateProcess(executable,new StringBuilder("\""+executable+"\" "+args),IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,AppDomain.CurrentDomain.BaseDirectory,ref startup,out info))throw new Exception("private fixture creation failed");
        try{var process=Process.GetProcessById((int)info.Pid);if(process.Handle==IntPtr.Zero){process.Dispose();throw new Exception("owned fixture handle missing");}return process;}
        finally{CloseHandle(info.Thread);CloseHandle(info.Process);}
    }
    static int NativeTarget(string readyName,string stopName){
        IntPtr window=CreateWindowEx(0x08000000,"STATIC","Owned startup decision fixture",0x00cf0000,100,100,800,600,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
        if(window==IntPtr.Zero)return 3;
        try{using(var ready=EventWaitHandle.OpenExisting(readyName))using(var stop=EventWaitHandle.OpenExisting(stopName)){
            ShowWindow(window,4);ready.Set();var clock=Stopwatch.StartNew();
            while(!stop.WaitOne(10)&&clock.ElapsedMilliseconds<20000){Message message;while(PeekMessage(out message,IntPtr.Zero,0,0,1)){TranslateMessage(ref message);DispatchMessage(ref message);}}
            return 0;
        }}finally{DestroyWindow(window);}
    }
    static object NativeField(string name){return typeof(NativeHandoff).GetField(name,BindingFlags.Static|BindingFlags.NonPublic).GetValue(null);}
    static void NativeSuite(string desktop){
        string suffix=Guid.NewGuid().ToString("N"),readyName="Local\\WarmReady"+suffix,stopName="Local\\WarmStop"+suffix;
        using(var ready=new EventWaitHandle(false,EventResetMode.ManualReset,readyName))using(var stop=new EventWaitHandle(false,EventResetMode.ManualReset,stopName))
        using(var child=StartPrivate(desktop,"--native-target "+readyName+" "+stopName)){
            try{
                Check(ready.WaitOne(3000),"owned target ready on private desktop");
                NativeHandoff.ClearUncommittedBridgeTarget();
                var settings=new Settings{Exe=Assembly.GetExecutingAssembly().Location,AppId="",WallpaperEnabled=false};
                var target=ExistingReplayTarget.FindUncommitted(settings,AppDomain.CurrentDomain.BaseDirectory);
                Check(target!=null&&BridgeActivation.WindowProcessId(target.Window)==(uint)child.Id,"uncommitted lookup selects owned fixture generation");
                Check(((IDictionary)NativeField("VerifiedTargets")).Count==0&&((IDictionary)NativeField("ProcessCache")).Count==0&&NativeField("bridgeTarget")==null,"uncommitted observation publishes no native or bridge cache");
                Check(target.IsCurrent,"uncommitted target validates without global cache");
                Check(((IDictionary)NativeField("VerifiedTargets")).Count==0&&((IDictionary)NativeField("ProcessCache")).Count==0,"uncommitted current check remains pure");
                Check(target.CommitSelection()&&NativeHandoff.FindCurrentStillValid(target.Window),"accepted caller commits exact owned target");
                Check(((IDictionary)NativeField("VerifiedTargets")).Count==1,"only accepted target becomes native capability");
                stop.Set();Check(child.WaitForExit(2500),"owned target exits cooperatively");
                Check(!target.IsCurrent&&!target.CommitSelection(),"ended pinned generation cannot recommit or retarget");
                NativeHandoff.ClearUncommittedBridgeTarget();
                Check(((IDictionary)NativeField("VerifiedTargets")).Count==0&&((IDictionary)NativeField("ProcessCache")).Count==0&&NativeField("bridgeTarget")==null,"cold transition clears prior authorization");
            }finally{stop.Set();if(!child.HasExited)Check(child.WaitForExit(2500),"owned target cleanup completes");}
        }
    }
    static void NativeParent(string output){
        string name="CodexWarmTest"+Guid.NewGuid().ToString("N");IntPtr desktop=CreateDesktop(name,IntPtr.Zero,IntPtr.Zero,0,0x1ff,IntPtr.Zero);
        Check(desktop!=IntPtr.Zero,"non-input fixture desktop created");
        try{using(var child=StartPrivate(name,"--native-suite "+name+" \""+output+"\"")){
            Check(child.WaitForExit(15000),"native private suite has bounded lifetime");
            Check(child.ExitCode==0,"native private suite passes: "+(File.Exists(output)?File.ReadAllText(output):"no receipt"));
        }}finally{CloseDesktop(desktop);}
    }
    [STAThread] static int Main(string[] args){
        try{
            if(args.Length==3&&args[0]=="--native-target")return NativeTarget(args[1],args[2]);
            if(args.Length==3&&args[0]=="--native-suite"){
                try{NativeSuite(args[1]);File.WriteAllText(args[2],"{\"passed\":true,\"checks\":"+checks+",\"privateNonInputDesktop\":true}");return 0;}
                catch(Exception error){File.WriteAllText(args[2],error.Message);return 1;}
            }
            DecisionCases();HostStatusCases();LateObservationCase();LateActivationCases();NativeParent(Path.Combine(args[0],"native-results.json"));
            Console.WriteLine("{\"passed\":true,\"checks\":"+checks+",\"actualCodexStarted\":false,\"syntheticDecisionsAndPrivateDesktop\":true}");return 0;
        }catch(Exception error){Console.WriteLine("FAIL: "+error);return 1;}
    }
}
}
