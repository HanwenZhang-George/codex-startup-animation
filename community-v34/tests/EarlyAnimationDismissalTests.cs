using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace DragonLauncher {
// Actual button routing / Window.Close / late bridge release, without Show,
// media decoding, a guardian, or any installed app lookup/activation.
internal static class EarlyAnimationDismissalTests {
    const BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
    static int checks,failures;
    static readonly bool sharedSkip=typeof(FilmSplash).GetMethod("BindPulseDismissal",Private)!=null;
    static readonly List<object> results=new List<object>();
    static object Read(object owner,string field){return owner.GetType().GetField(field,Private).GetValue(owner);}
    static void Write(object owner,string field,object value){owner.GetType().GetField(field,Private).SetValue(owner,value);}
    static object Invoke(object owner,string method,params object[] args){return owner.GetType().GetMethod(method,Private).Invoke(owner,args);}
    static void Check(bool value,string reason){checks++;if(!value)throw new Exception(reason);}
    sealed class Peer:IDisposable {
        readonly NamedPipeServerStream pipe;readonly Thread worker;
        internal string Command;internal Exception Failure;
        internal Peer(string token){
            pipe=new NamedPipeServerStream(BridgeActivation.PipeName(token),PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous);
            worker=new Thread(()=>{
                try{
                    var waiting=pipe.BeginWaitForConnection(null,null);
                    try{if(!waiting.AsyncWaitHandle.WaitOne(2000))throw new TimeoutException("owned peer connection");pipe.EndWaitForConnection(waiting);}finally{waiting.AsyncWaitHandle.Close();}
                    using(var input=new MemoryStream()){
                        for(int i=0;i<96;i++){int next=pipe.ReadByte();if(next<0)throw new EndOfStreamException();if(next==10)break;input.WriteByte((byte)next);}
                        Command=Encoding.UTF8.GetString(input.ToArray());
                    }
                    using(var process=Process.GetCurrentProcess()){
                        long created;BridgeNative.CreationTime(process.Handle,out created);
                        var status=new BridgeStatus{Version=1,Disposition=2,HostPid=process.Id,HostCreated=created,CodexPid=process.Id,CodexCreated=created,MediaCode=4,Ready=true};
                        using(var output=new MemoryStream()){
                            new DataContractJsonSerializer(typeof(BridgeStatus)).WriteObject(output,status);byte[] bytes=output.ToArray();pipe.Write(bytes,0,bytes.Length);pipe.WriteByte(10);pipe.Flush();
                        }
                    }
                }catch(Exception error){Failure=error;}
            }){IsBackground=true};worker.Start();
        }
        internal void Finish(){Check(worker.Join(2500),"owned peer bounded completion");Check(Failure==null,"owned peer protocol succeeds");}
        public void Dispose(){pipe.Dispose();worker.Join(500);}
    }
    static FilmSplash Film(string media,bool pending=true,bool preview=false){
        var settings=new Settings{AppId="",Exe=Path.Combine(Path.GetDirectoryName(media),"missing-test-client.exe"),
            StartupIntroFile=media,StartupIdleFile=media,StartupFinaleFile=media,WallpaperEnabled=true};
        Check(!File.Exists(settings.Exe),"test activation target is guaranteed absent");
        var film=new FilmSplash(media,settings,true,true);
        Write(film,"preview",preview);
        // Pretend activation has been requested. The synthetic result is passed
        // below; this deliberately prevents all real EnsureActivation work.
        Write(film,"activationRequested",pending);
        Check(Read(film,"recoveryGuard")==null&&!film.IsVisible,"fixture never shows a native window or starts guardian");
        return film;
    }
    static PulseReveal BindPulse(FilmSplash film,string still){
        var pulse=new PulseReveal(still,0.5,true);Write(film,"pulse",pulse);Write(film,"transitioning",true);
        if(sharedSkip)Invoke(film,"BindPulseDismissal",pulse);
        else {
            // Frozen R15's exact production event connections, extracted here
            // only because PreparePulse also shows a real compositor window.
            // The real PulseReveal button and Window.Close events still fire.
            pulse.Dismissed+=delegate {Invoke(film,"CancelHandoff");};
            pulse.SkipRequested+=delegate {Invoke(film,"SkipAnimation");};
            pulse.Closed+=delegate(object sender,EventArgs e){
                if(object.ReferenceEquals(Read(film,"pulse"),sender))Write(film,"pulse",null);
                if(!(bool)Read(film,"done")&&!(bool)Read(film,"cleaned")){
                    Write(film,"pulsePreparationFailed",true);
                    if((bool)Read(film,"transitioning"))Invoke(film,"CancelHandoff");
                }
            };
        }
        Check(!pulse.IsVisible,"pulse fixture never shows native window");return pulse;
    }
    static void Dismiss(FilmSplash film,string route,PulseReveal pulse=null){
        if(route=="button")((Button)Read(film,"cancel")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        else if(route=="window-close")film.Close();
        else if(route=="pulse-button")((Button)Read(pulse,"dismiss")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        else if(route=="pulse-close")pulse.Close();
        else if(route=="resource-protection")Invoke(film,"SkipAnimationCore",true);
        else if(route=="compatibility-fallback")Invoke(film,"LaunchClose");
        else Invoke(film,"SkipAnimation");
    }
    static void Cleanup(FilmSplash film){
        if(film==null||(bool)Read(film,"cleaned"))return;
        // Test teardown never re-enters a user skip or starts activation.
        Write(film,"done",true);film.Close();
    }
    static void Case(string media,string still,string route,bool late,bool terminal){
        string token=Guid.NewGuid().ToString("N"),observed=null,error=null;
        FilmSplash film=null;PulseReveal pulse=null;int closing=0,closed=0,pulseClosing=0,pulseClosed=0;
        try{using(var peer=new Peer(token))using(var release=new ManualResetEvent(false)){
            film=Film(media);
            var session=new BridgeSession(Process.GetCurrentProcess(),token,null);
            if(!late)Write(film,"wallpaperSession",session);
            else {
                // Exercise the actual late activation worker / cleanup path.
                Invoke(film,"StartActivationWorker",new Func<BridgeResult>(delegate {
                    if(!release.WaitOne(2000))throw new TimeoutException("synthetic activation release");
                    return new BridgeResult{Session=session,Code="owned-synthetic-session"};
                }),false);
            }
            if(route.StartsWith("pulse-",StringComparison.Ordinal)){
                pulse=BindPulse(film,still);pulse.Closing+=delegate {pulseClosing++;};pulse.Closed+=delegate {pulseClosed++;};
            }
            film.Closing+=delegate {closing++;};film.Closed+=delegate {closed++;};
            if(terminal)Invoke(film,"DisableUnpreparedWallpaper",new object[]{null});
            try{Dismiss(film,route,pulse);}finally{release.Set();}
            if(late)Check(((ManualResetEvent)Read(film,"activationCompleted")).WaitOne(2500),"late activation worker finishes within bound");
            Check((bool)Read(film,"cleaned")&&(bool)Read(film,"done"),"real dismissal completes cleanup");
            Check(closing==1&&closed==1,"real film Closing/Closed fire exactly once without recursion");
            if(pulse!=null){Check(pulseClosing==1&&pulseClosed==1,"real pulse Closing/Closed fire exactly once without recursion");Check(Read(film,"pulse")==null&&(bool)Read(pulse,"stopped"),"closed pulse released before film cleanup");}
            Check(!film.HandoffSucceeded&&!film.PlaybackSucceeded,"dismissal never claims successful handoff");
            peer.Finish();observed=peer.Command;
            Check(observed==(terminal?"disable":"reveal"),"expected "+(terminal?"disable":"reveal")+", observed "+observed);
            Check((int)Read(film,"wallpaperRevealRequested")== (terminal?-1:1),"dismissal preserves explicit wallpaper intent");
            Check((bool)Read(Read(film,"living"),"disposed")&&!(bool)Read(Read(film,"living"),"started"),"fixture never decodes and releases media controller");
        }}catch(Exception failure){error=failure.GetBaseException().Message;failures++;}
        finally{Cleanup(film);}
        results.Add(new {route=route,lateSession=late,priorTerminalDisable=terminal,passed=error==null,observedCommand=observed,error=error,
            filmClosing=closing,filmClosed=closed,pulseClosing=pulseClosing,pulseClosed=pulseClosed});
    }
    sealed class TestApplication:Application {
        internal void SimulateSessionEnding(){
            var e=(SessionEndingCancelEventArgs)Activator.CreateInstance(typeof(SessionEndingCancelEventArgs),
                BindingFlags.Instance|BindingFlags.NonPublic,null,new object[]{ReasonSessionEnding.Logoff},null);
            OnSessionEnding(e);
        }
    }
    static TestApplication SubscriptionCase(string media){
        FilmSplash film=null;TestApplication app=null;string error=null;
        try {
            film=Film(media,false);app=new TestApplication{ShutdownMode=ShutdownMode.OnExplicitShutdown};
            if(sharedSkip){
                Check(Read(film,"sessionApplication")==null,"film may precede Application creation");
                Invoke(film,"ObserveSessionEnding");Invoke(film,"ObserveSessionEnding");
                Check(object.ReferenceEquals(Read(film,"sessionApplication"),app),"late Application subscribes once before actual source initialization");
                app.SimulateSessionEnding();Check((bool)Read(film,"sessionEnding"),"real managed Application.SessionEnding reaches film");
                film.Close();Check(Read(film,"sessionApplication")==null,"close detaches SessionEnding subscription");
                Write(film,"sessionEnding",false);app.SimulateSessionEnding();Check(!(bool)Read(film,"sessionEnding"),"closed film receives no session callback");
                Check(!(bool)Read(film,"activationRequested")&&(int)Read(film,"wallpaperRevealRequested")==0,"session shutdown never requests activation or reveal");
            }else Cleanup(film);
        }catch(Exception failure){error=failure.GetBaseException().Message;failures++;}
        finally{Cleanup(film);}
        results.Add(new {route="session-subscription",versionSpecific=sharedSkip,passed=error==null,error=error});return app;
    }
    static void GuardCase(string media,string still,TestApplication app,string guard,bool pulseRoute){
        FilmSplash film=null;PulseReveal pulse=null;string error=null;int closing=0,closed=0;
        try{
            film=Film(media,false,guard=="preview");
            film.Closing+=delegate {closing++;};film.Closed+=delegate {closed++;};
            if(pulseRoute)pulse=BindPulse(film,still);
            if(guard=="done")Write(film,"done",true);
            if(guard=="session-ending"&&sharedSkip)app.SimulateSessionEnding();
            if(guard=="internal-failure")Invoke(film,"FailLiving","synthetic internal preparation failure",false);
            else {if(pulseRoute)pulse.Close();if(!(bool)Read(film,"cleaned"))film.Close();}
            Check(!(bool)Read(film,"activationRequested"),"non-user close never starts activation");
            Check((int)Read(film,"wallpaperRevealRequested")== (guard=="internal-failure"?-1:0),"non-user close never publishes reveal");
            Check(!(bool)Read(film,"userSkipped")&&!(bool)Read(film,"resourceSkipped"),"non-user close never becomes successful skip");
            Check(closing==1&&closed==1,"non-user real Closing/Closed have no recursion");
        }catch(Exception failure){error=failure.GetBaseException().Message;failures++;}
        finally{Cleanup(film);}
        results.Add(new {route=pulseRoute?"pulse-close":"window-close",guard=guard,passed=error==null,error=error});
    }
    static void DispatcherShutdownCase(string media){
        string error=null;
        var thread=new Thread(delegate(){FilmSplash film=null;try{
            film=Film(media,false);Dispatcher.CurrentDispatcher.InvokeShutdown();
            film.Close();
            Check(!(bool)Read(film,"activationRequested")&&(int)Read(film,"wallpaperRevealRequested")==0,"dispatcher shutdown close never activates or reveals");
            Check(!(bool)Read(film,"userSkipped")&&(bool)Read(film,"cleaned"),"dispatcher shutdown does actual cleanup without skip");
        }catch(Exception failure){error=failure.GetBaseException().Message;}finally{Cleanup(film);}});
        thread.SetApartmentState(ApartmentState.STA);thread.Start();
        if(!thread.Join(3500))error="dispatcher fixture did not finish within bound";
        if(error!=null)failures++;results.Add(new {route="dispatcher-shutdown",passed=error==null,error=error});
    }
    static void BeforeActivationCase(string media,string still,string route){
        FilmSplash film=null;string error=null;
        try{
            film=Film(media,false);PulseReveal pulse=route.StartsWith("pulse-",StringComparison.Ordinal)?BindPulse(film,still):null;
            Dismiss(film,route,pulse);
            Check((bool)Read(film,"activationRequested"),"early dismissal requests ordinary startup exactly once");
            Check(((ManualResetEvent)Read(film,"activationCompleted")).WaitOne(2500),"missing synthetic executable fails boundedly without app launch");
            Check((int)Read(film,"wallpaperRevealRequested")==1&&(bool)Read(film,"cleaned"),"early dismissal publishes reveal before clean shutdown");
        }catch(Exception failure){error=failure.GetBaseException().Message;failures++;}
        finally{Cleanup(film);}
        results.Add(new {route=route,beforeActivation=true,passed=error==null,error=error});
    }
    static void DiagnosticCases(){
        if(!sharedSkip)return;string error=null;
        try{
            var wait=Stopwatch.StartNew();
            while((bool)typeof(LauncherDiagnostics).GetField("running",BindingFlags.Static|BindingFlags.NonPublic).GetValue(null)&&wait.ElapsedMilliseconds<2000)Thread.Sleep(10);
            string text=File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"output","handoff-latest.log"));
            foreach(string source in new[]{"keyboard","movie-button","pulse-button","window-close","resource-protection","compatibility-fallback"})
                Check(text.Contains("animation-skip source="+source+" wallpaperIntent=reveal activationRequested=True"),"fixed diagnostic source emitted: "+source);
            Check(text.Contains("wallpaperIntent=disabled activationRequested=True"),"terminal disabled intent diagnostic is explicit");
        }catch(Exception failure){error=failure.GetBaseException().Message;failures++;}
        results.Add(new {route="fixed-diagnostics",passed=error==null,error=error});
    }
    [STAThread] static int Main(string[] args){
        try{
            string media=Path.Combine(args[0],"never-played-dismissal-fixture.mp4");File.WriteAllBytes(media,new byte[]{0});
            string still=Path.Combine(args[0],"synthetic-pulse.png");
            var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(1,1,96,96,PixelFormats.Bgra32,null,new byte[]{0,0,0,255},4)));
            using(var output=File.Create(still))encoder.Save(output);
            DispatcherShutdownCase(media);
            TestApplication app=SubscriptionCase(media);
            Case(media,still,"skip-control",false,false);
            foreach(string route in new[]{"button","window-close","pulse-button","pulse-close"}){
                Case(media,still,route,false,false);Case(media,still,route,true,false);
                Case(media,still,route,false,true);Case(media,still,route,true,true);
                BeforeActivationCase(media,still,route);
            }
            Case(media,still,"resource-protection",false,false);Case(media,still,"compatibility-fallback",false,false);
            foreach(string guard in new[]{"done","preview","internal-failure","session-ending"}){
                // System session state did not exist in R15. Its new guard is
                // classified separately from the shared behavior regressions.
                if(guard=="session-ending"&&!sharedSkip)continue;
                GuardCase(media,still,app,guard,false);GuardCase(media,still,app,guard,true);
            }
            DiagnosticCases();
            Console.WriteLine(new JavaScriptSerializer().Serialize(new {passed=failures==0,checks=checks,failures=failures,actualCodexStarted=false,nativeWindowsShown=false,mediaDecoded=false,ownedPrivatePipe=true,
                pulseBinding=sharedSkip?"production-helper":"frozen-r15-event-connections",cases=results}));
            return failures==0?0:1;
        }catch(Exception failure){Console.WriteLine("FAIL: "+failure.GetBaseException().Message);return 1;}
    }
}
}
