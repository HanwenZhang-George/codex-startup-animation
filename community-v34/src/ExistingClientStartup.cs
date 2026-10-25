using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace DragonLauncher
{
    internal enum WarmHostState { Unchecked, Unavailable, Unverified, Managed, Disabled, Paused, Faulted, AnimationOnly }
    internal enum WarmStartupDecision { Cold, Replay, Cancelled, Unavailable }
    internal sealed class WarmStartupResult<T> where T : class
    {
        internal WarmStartupDecision Decision;
        internal T Target;
        internal string Reason;
        internal WarmHostState HostState;
        internal int ActivationCount;
    }

    // A timed-out read may finish later. Observations never publish native
    // identities; a timeout is terminal and cannot enter a subsequent launch.
    internal sealed class WarmObservation
    {
        private readonly object gate=new object();
        private bool open=true;
        internal void Publish(Action publish){lock(gate){if(open)publish();}}
        internal void Close(){lock(gate){open=false;}}
    }
    internal sealed class WarmStartupHooks<T> where T : class
    {
        internal Func<WarmObservation,T> Find;
        internal Func<T,bool> IsCurrent;
        internal Func<bool> IsRunning;
        internal Action<int> Activate;
        internal Func<T,WarmHostState> InspectHost;
        internal Func<bool,bool> AskRetry;
        internal Func<long> Elapsed;
        internal Action<int> Delay;
        internal Action ClearUncommitted;
        internal Func<Func<WarmObservation,object>,int,object> Read;
    }

    internal static class ExistingClientStartup
    {
        internal const int AutomaticTimeoutMilliseconds=8000;
        internal static bool ShouldCoordinate(Settings settings,bool preview)
        {return !preview&&settings!=null&&String.IsNullOrWhiteSpace(settings.Exe)&&String.Equals(settings.AppId,BridgeClientIdentity.OfficialAppId,StringComparison.OrdinalIgnoreCase);}
        private static int Remaining(long deadline,long now)
        {return (int)Math.Max(0,Math.Min(AutomaticTimeoutMilliseconds,deadline-now));}
        private static string HostName(WarmHostState state)
        {
            switch(state){
                case WarmHostState.Unavailable:return "unavailable";
                case WarmHostState.Unverified:return "unverified";
                case WarmHostState.Managed:return "managed";
                case WarmHostState.Disabled:return "disabled";
                case WarmHostState.Paused:return "paused";
                case WarmHostState.Faulted:return "faulted";
                case WarmHostState.AnimationOnly:return "animation-only";
                default:return "unchecked";
            }
        }
        private static bool Managed(WarmHostState state)
        {return state==WarmHostState.Managed||state==WarmHostState.Disabled||state==WarmHostState.Paused||state==WarmHostState.Faulted;}
        private static void Record<T>(WarmStartupHooks<T> hooks,Action<string> log,long started,int activations,WarmHostState host,string decision,string reason) where T : class
        {
            try{if(log!=null)log("warm-start decision="+decision+" reason="+reason+" elapsedMs="+
                Math.Max(0,Math.Min(86400000,hooks.Elapsed()-started)).ToString(System.Globalization.CultureInfo.InvariantCulture)+
                " activationCount="+activations.ToString(System.Globalization.CultureInfo.InvariantCulture)+" hostState="+HostName(host));}catch{}
        }
        private static U Observe<T,U>(WarmStartupHooks<T> hooks,long deadline,Func<WarmObservation,U> read) where T : class
        {
            int remaining=Remaining(deadline,hooks.Elapsed());
            if(remaining<=0)throw new TimeoutException();
            U result=(U)hooks.Read(scope=>(object)read(scope),remaining);
            if(Remaining(deadline,hooks.Elapsed())<=0)throw new TimeoutException();
            return result;
        }
        private static WarmStartupResult<T> Result<T>(WarmStartupHooks<T> hooks,Action<string> log,long started,int activations,WarmHostState host,WarmStartupDecision decision,string reason,T target=null) where T : class
        {
            if(decision==WarmStartupDecision.Cold)hooks.ClearUncommitted();
            Record(hooks,log,started,activations,host,decision.ToString().ToLowerInvariant(),reason);
            return new WarmStartupResult<T>{Decision=decision,Reason=reason,Target=target,HostState=host,ActivationCount=activations};
        }

        // Every mutating activation is explicit and issued at most once. Reads
        // after activation are bounded by the ORIGINAL deadline. Only a later
        // user Retry can authorize a fresh absence check and the cold route.
        internal static WarmStartupResult<T> Decide<T>(bool wallpaper,WarmStartupHooks<T> hooks,Action<string> log=null) where T : class
        {
            long started=hooks.Elapsed(),deadline=started+AutomaticTimeoutMilliseconds;
            int activations=0;WarmHostState host=WarmHostState.Unchecked;T target;
            try{
                target=Observe(hooks,deadline,scope=>hooks.Find(scope));
                if(target==null){
                    if(!Observe(hooks,deadline,scope=>hooks.IsRunning()))
                        return Result(hooks,log,started,activations,host,WarmStartupDecision.Cold,"no-running");
                    int budget=Math.Min(4000,Remaining(deadline,hooks.Elapsed()));
                    if(budget<=0)throw new TimeoutException();
                    activations=1;Record(hooks,log,started,activations,host,"activate","no-window");
                    try{hooks.Activate(budget);}
                    catch(Exception error){return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,
                        error.GetBaseException() is TimeoutException?"activation-timeout":"activation-failed");}
                    while(Remaining(deadline,hooks.Elapsed())>0){
                        target=Observe(hooks,deadline,scope=>hooks.Find(scope));
                        if(target!=null)break;
                        int delay=Math.Min(100,Remaining(deadline,hooks.Elapsed()));
                        if(delay>0)hooks.Delay(delay);
                    }
                    if(target==null)return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,"window-timeout");
                }
                if(!Observe(hooks,deadline,scope=>hooks.IsCurrent(target)))
                    return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,"target-ended");
                if(!wallpaper){
                    host=WarmHostState.AnimationOnly;
                    return Result(hooks,log,started,activations,host,WarmStartupDecision.Replay,"animation-only",target);
                }
                host=Observe(hooks,deadline,scope=>hooks.InspectHost(target));
                if(!Observe(hooks,deadline,scope=>hooks.IsCurrent(target)))
                    return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,"target-ended");
                if(Managed(host))return Result(hooks,log,started,activations,host,WarmStartupDecision.Replay,
                    activations==0?"existing-window":"window-recovered",target);
            }catch(Exception error){return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,
                error.GetBaseException() is TimeoutException?"observation-timeout":"identity-unavailable");}

            Record(hooks,log,started,activations,host,"needs-exit","host-unavailable");
            bool stillRunning=false;
            for(;;){
                if(!hooks.AskRetry(stillRunning))
                    return Result(hooks,log,started,activations,host,WarmStartupDecision.Cancelled,"user-cancelled");
                // The user has now explicitly requested a new attempt after
                // fully exiting. Never activate again inside this decision loop.
                try{
                    bool running=Observe(hooks,hooks.Elapsed()+AutomaticTimeoutMilliseconds,scope=>hooks.IsRunning());
                    if(!running)return Result(hooks,log,started,activations,host,WarmStartupDecision.Cold,"manual-retry-cold");
                    stillRunning=true;Record(hooks,log,started,activations,host,"needs-exit","manual-retry-running");
                }catch(Exception error){return Result(hooks,log,started,activations,host,WarmStartupDecision.Unavailable,
                    error.GetBaseException() is TimeoutException?"observation-timeout":"identity-unavailable");}
            }
        }

        internal static object BoundedRead(Func<WarmObservation,object> read,int milliseconds)
        {
            var scope=new WarmObservation();Task<object> work=Task.Run(()=>read(scope));
            work.ContinueWith(task=>{var ignored=task.Exception;},TaskContinuationOptions.OnlyOnFaulted);
            try{
                if(!work.Wait(Math.Max(1,milliseconds)))throw new TimeoutException("warm-observation-timeout");
                return work.GetAwaiter().GetResult();
            }finally{scope.Close();}
        }
        private static ExistingReplayTarget FindVerified(ExistingReplayTarget.UncommittedSearch search)
        {
            var target=search.Find();
            if(target==null)return null;
            uint pid=BridgeActivation.WindowProcessId(target.Window);
            using(var process=BridgeNative.OpenReadProcess(pid)){
                long created;IntPtr handle=process.DangerousGetHandle();
                if(!BridgeNative.IsAlive(handle)||!BridgeNative.CreationTime(handle,out created))return null;
                using(var official=CodexDragon.Official.OfficialIdentityResolver.VerifyProcess((int)pid,created)){
                    if(!BridgeNative.SameSession(pid)||!target.IsCurrent||BridgeActivation.WindowProcessId(target.Window)!=pid||
                        !String.Equals(official.Executable,BridgeNative.ImagePath(handle),StringComparison.OrdinalIgnoreCase))return null;
                }
            }
            return target;
        }
        private static WarmHostState InspectHost(Settings settings,string root,ExistingReplayTarget target,Action<string> log)
        {
            uint pid=BridgeActivation.WindowProcessId(target.Window);
            using(var session=BridgeActivation.Discover(root,pid,log)){
                if(session==null)return WarmHostState.Unavailable;
                var identity=BridgeClientIdentity.Attest(settings,root,session,log);
                if(identity==null||!target.IsCurrent)return WarmHostState.Unverified;
                using(var process=BridgeNative.OpenReadProcess(pid)){
                    long created;IntPtr handle=process.DangerousGetHandle();
                    if(!BridgeNative.IsAlive(handle)||!BridgeNative.CreationTime(handle,out created)||
                        !identity.Matches(pid,created,BridgeNative.ImagePath(handle))||
                        BridgeActivation.WindowProcessId(target.Window)!=pid)return WarmHostState.Unverified;
                }
                BridgeStatus status=session.LastStatus;
                if(status==null||session.HostExited||!target.IsCurrent)return WarmHostState.Unverified;
                return ClassifyManagedHost(status);
            }
        }
        internal static WarmHostState ClassifyManagedHost(BridgeStatus status)
        {
            // User disable retires decoration with MediaCode=6. Preserve that
            // explicit intent instead of diagnosing it as a renderer failure.
            if(status.DesiredMode=="disabled")return WarmHostState.Disabled;
            if(status.MediaCode>=6)return WarmHostState.Faulted;
            if(status.Disabled)return WarmHostState.Disabled;
            if(status.DesiredMode=="user-paused"||status.MediaCode==5)return WarmHostState.Paused;
            return WarmHostState.Managed;
        }
        private static bool AskRetry(bool stillRunning)
        {
            string text=(stillRunning?"仍检测到 Codex 后台进程，尚未重新启动。\n\n":"当前 Codex 不是由本包建立的可验证壁纸会话；仅重播动画不会启用动态壁纸。\n\n")+
                "请先保存工作，再从 Codex 完整退出。只关闭窗口可能仍保留后台进程。\n\n"+
                "完整退出后点击“重试”，将从本包重新启动并启用壁纸；点击“取消”保留当前客户端。\n\n"+
                "本提示不会关闭或终止 Codex。你可以切换到 Codex 操作。";
            // Unowned dialog: only this launcher's thread is modal. The Codex
            // window is neither disabled nor covered by an animation/input guard.
            return System.Windows.Forms.MessageBox.Show(text,"Codex 动态壁纸",System.Windows.Forms.MessageBoxButtons.RetryCancel,
                System.Windows.Forms.MessageBoxIcon.Information,System.Windows.Forms.MessageBoxDefaultButton.Button2)==System.Windows.Forms.DialogResult.Retry;
        }
        internal static WarmStartupResult<ExistingReplayTarget> Resolve(Settings settings,string root,Action<string> log)
        {
            var clock=Stopwatch.StartNew();
            var search=new ExistingReplayTarget.UncommittedSearch(settings,root,log);
            var hooks=new WarmStartupHooks<ExistingReplayTarget>{
                Find=scope=>FindVerified(search),IsCurrent=target=>target.IsCurrent,
                IsRunning=()=>CodexDragon.Official.OfficialIdentityResolver.IsOfficialRunning(),
                Activate=budget=>{AppActivation.OpenBounded(settings,budget);},
                InspectHost=target=>InspectHost(settings,root,target,log),AskRetry=AskRetry,
                Elapsed=()=>clock.ElapsedMilliseconds,Delay=Thread.Sleep,
                ClearUncommitted=NativeHandoff.ClearUncommittedBridgeTarget,Read=BoundedRead
            };
            var result=Decide(settings.WallpaperEnabled,hooks,log);
            if(result.Decision==WarmStartupDecision.Replay&&!result.Target.CommitSelection())
                return Result(hooks,log,0,result.ActivationCount,result.HostState,WarmStartupDecision.Unavailable,"target-ended");
            return result;
        }
    }
}
