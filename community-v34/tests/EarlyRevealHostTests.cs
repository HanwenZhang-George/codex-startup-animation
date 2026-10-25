using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace CodexDragonWallpaper {
// The actual HostState, WallpaperSession.Run, CdpTransport.Send and Frame run
// here. Only the browser/renderer peer is synthetic. No executable is launched,
// no window is shown and no media is decoded. This is controller evidence, not
// evidence of visible pixels or playback on an installed Codex client.
internal static class EarlyRevealHostTests {
    const BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
    static int checks;
    static readonly List<object> cases=new List<object>();
    static void Set(object owner,string name,object value){owner.GetType().GetField(name,Private).SetValue(owner,value);}
    static object Get(object owner,string name){return owner.GetType().GetField(name,Private).GetValue(owner);}
    static void Check(bool value,string text){Interlocked.Increment(ref checks);if(!value)throw new Exception(text);}
    static bool Until(Func<bool> predicate,int budget){var clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<budget){if(predicate())return true;Thread.Sleep(10);}return predicate();}
    sealed class Request {internal Dictionary<string,object> Packet;internal string Kind;internal int Phase;}
    sealed class Peer:FileStream {
        internal Fixture Owner;
        internal Action<Request> Before;
        internal volatile bool AllowPrepared,Attached,Revealed,Disposed,ManualPause;
        internal long Generation;
        internal string Document;
        readonly Dictionary<string,int> counts=new Dictionary<string,int>();
        internal Peer(string path):base(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.ReadWrite,1,FileOptions.Asynchronous){}
        internal int Count(string kind){lock(counts){int count;return counts.TryGetValue(kind,out count)?count:0;}}
        void Reply(Request request,object value,bool raw=false){
            var packet=Json.Obj("id",Json.Get(request.Packet,"id"),"result",raw?value:Json.Obj("result",Json.Obj("type","object","value",value)));
            if(request.Packet.ContainsKey("sessionId"))packet["sessionId"]=Json.Get(request.Packet,"sessionId");
            byte[] bytes=Encoding.UTF8.GetBytes(Json.Serializer().Serialize(packet));
            typeof(CdpTransport).GetMethod("Frame",Private).Invoke(Owner.Transport,new object[]{bytes,bytes.Length});
        }
        Dictionary<string,object> Status(){
            bool ready=Attached&&AllowPrepared&&!Disposed,playing=ready&&Revealed&&!ManualPause;
            return Json.Obj("attached",Attached&&!Disposed,"mediaReady",ready,"prepared",ready,"disposed",Disposed,"playing",playing,"wallpaperApplied",playing,
                "revealed",Revealed,"layoutSupported",true,"manuallyPaused",ManualPause,"probeOnly",false,"firstFrameConfirmed",playing,
                "documentHidden",false,"stageVisible",playing,"code",Disposed?"disposed":ready?Revealed?"playing":"prepared":"loading","mediaTimeMs",playing?120:0,
                "documentGeneration",Document??Owner.State.DocumentGeneration,"protocolVersion",2,"leaseNeedsRenew",false,"mediaGeneration",Generation,
                "actualPhase",Disposed?"retired":ready?Revealed?"visible":"prepared":"preparing","health","fresh","prepareOperationId","","commitAccepted",false,
                "recoveryNeeded",false,"recoveryStable",false,"recoveryReason","","rendererClockMs",1000,"dormant",false,"memoryPressure",false);
        }
        void Respond(Request request){switch(request.Kind){
            case "discover":Reply(request,Json.Obj("targetInfos",new object[]{Json.Obj("targetId","owned_target","type","page","url","app://-/index.html")}),true);break;
            case "target-attach":Reply(request,Json.Obj("sessionId","owned_session"),true);break;
            case "root":Reply(request,Json.Obj("rootReady",true,"bodyReady",true));break;
            case "preflight":Reply(request,Json.Obj("namespaceFree",true,"ownNodeCount",0));break;
            case "install":Reply(request,Json.Obj("ok",true,"code","installed"));break;
            case "configure":Document=Owner.State.DocumentGeneration;Reply(request,Json.Obj("ok",true));break;
            case "binding":case "files":Reply(request,Json.Obj(),true);break;
            case "renew":Reply(request,Json.Obj("ok",true));break;
            case "media-attach":Attached=true;Generation=1;Reply(request,Json.Obj("ok",true));break;
            case "style":Reply(request,Json.Obj("styleAccepted",true));break;
            case "layout":case "status":Reply(request,Status());break;
            case "document":Reply(request,Json.Obj("root",Json.Obj("nodeId",1)),true);break;
            case "query":Reply(request,Json.Obj("nodeId",2),true);break;
            case "describe":Reply(request,Json.Obj("node",Json.Obj("backendNodeId",3,"nodeName","INPUT","attributes",new object[]{"id","codex-dragon-file-v1","type","file"})),true);break;
            case "input":Reply(request,Json.Obj("inputReady",true,"multiple",false));break;
            case "reveal":Revealed=true;ManualPause=false;Reply(request,Json.Obj("ok",true));break;
            case "pause":ManualPause=true;Reply(request,Json.Obj("ok",true));break;
            case "dispose":Disposed=true;Attached=false;Reply(request,Json.Obj("ok",true));break;
            case "cleanup":Reply(request,Json.Obj("apiPresent",false,"ownNodeCount",0,"markerPresent",false));break;
            default:throw new Exception("Unexpected synthetic renderer request: "+request.Kind);
        }}
        public override IAsyncResult BeginWrite(byte[] buffer,int offset,int count,AsyncCallback callback,object state){
            Check(count>0&&buffer[offset+count-1]==0,"real transport emits NUL-delimited requests");
            var packet=Json.Map(Json.Serializer().DeserializeObject(Encoding.UTF8.GetString(buffer,offset,count-1)));
            string method=Json.Text(packet,"method"),expression=Json.Text(Json.Map(Json.Get(packet,"params")),"expression")??"";
            var request=new Request{Packet=packet,Phase=(int)Get(Owner.Session,"phase")};
            if(method=="Target.getTargets")request.Kind="discover";
            else if(method=="Target.attachToTarget")request.Kind="target-attach";
            else if(method=="Runtime.addBinding")request.Kind="binding";
            else if(method=="DOM.getDocument")request.Kind="document";
            else if(method=="DOM.querySelector")request.Kind="query";
            else if(method=="DOM.describeNode")request.Kind="describe";
            else if(method=="DOM.setFileInputFiles")request.Kind="files";
            else if(expression.Contains(".attach("))request.Kind="media-attach";
            else if(expression.Contains(".renewLease("))request.Kind="renew";
            else if(expression.Contains(".reveal()"))request.Kind="reveal";
            else if(expression.Contains(".pause()"))request.Kind="pause";
            else if(expression.Contains("a.dispose()"))request.Kind="dispose";
            else if(expression.Contains("apiPresent:"))request.Kind="cleanup";
            else if(request.Phase==2)request.Kind="root";
            else if(request.Phase==3)request.Kind="preflight";
            else if(request.Phase==4)request.Kind=expression.Contains(".configure(")?"configure":"install";
            else if(request.Phase==5)request.Kind="style";
            else if(request.Phase==6)request.Kind="layout";
            else if(request.Phase==8)request.Kind="input";
            else request.Kind="status";
            lock(counts)counts[request.Kind]=Count(request.Kind)+1;
            if(Before!=null)Before(request);Respond(request);
            var result=new TaskCompletionSource<object>(state);result.SetResult(null);if(callback!=null)callback(result.Task);return result.Task;
        }
        public override void EndWrite(IAsyncResult result){((Task)result).GetAwaiter().GetResult();}
    }
    sealed class Fixture:IDisposable {
        internal readonly Peer Peer;
        internal readonly CdpTransport Transport;
        internal readonly HostState State;
        internal readonly WallpaperSession Session;
        readonly MemoryPressureMonitor memory;
        Thread worker;
        internal Exception Failure;
        internal Fixture(string directory){
            Peer=new Peer(Path.Combine(directory,Guid.NewGuid().ToString("N")+".fixture"));Peer.Owner=this;
            object owned=typeof(OwnedClient).GetConstructor(Private,null,new[]{typeof(FileStream),typeof(FileStream),typeof(string)},null).Invoke(new object[]{Peer,Peer,Path.Combine(directory,"never-launched.exe")});
            Transport=(CdpTransport)FormatterServices.GetUninitializedObject(typeof(CdpTransport));
            Set(Transport,"client",owned);Set(Transport,"gate",new object());Set(Transport,"writeGate",new object());
            FieldInfo pending=typeof(CdpTransport).GetField("pending",Private);pending.SetValue(Transport,Activator.CreateInstance(pending.FieldType));
            State=new HostState();Session=new WallpaperSession(Transport,State,new Configuration{Enabled=true,Media="owned-fixture.mp4",Renderer="({ok:true,code:'installed'})"},false);
            memory=new MemoryPressureMonitor(State.Work,null,null,null,null,()=>{memory.AvailableCommitBytes=12L*1024*1024*1024;memory.TotalCommitBytes=32L*1024*1024*1024;return 2;});
            Set(Session,"memoryFactory",new Func<WaitHandle,MemoryPressureMonitor>(_=>memory));
        }
        internal void Start(){worker=new Thread(()=>{try{Session.Run();}catch(Exception error){Failure=error;}}){IsBackground=true};worker.Start();}
        internal bool Ended {get{return worker!=null&&!worker.IsAlive;}}
        internal void WaitPreparing(){Check(Until(()=>Peer.Count("media-attach")==1&&Peer.Count("status")>0,2500),"actual Run reaches deferred first-frame preparation");Check(!State.Ready&&!State.Playing&&!State.Disabled,"preparation does not invent ready playback");}
        internal void Allow(){Peer.AllowPrepared=true;State.Work.Set();}
        internal void NoRepeatedMutations(){
            foreach(string kind in new[]{"target-attach","install","binding","configure","files","media-attach"})Check(Peer.Count(kind)<=1,"no repeated mutation: "+kind);
            Check(((IDictionary)Get(Transport,"pending")).Count==0,"no abandoned CDP request");
        }
        internal void Stop(){State.Command("disable");Check(worker==null||worker.Join(3000),"owned controller exits within cleanup bound");}
        public void Dispose(){if(worker!=null&&worker.IsAlive)Stop();Peer.Dispose();memory.Dispose();State.Work.Dispose();State.TerminalRead.Dispose();}
    }
    static void EarlyReveal(string directory,bool beforeStart){using(var f=new Fixture(directory)){
        if(beforeStart)f.State.Command("reveal");
        f.Start();f.WaitPreparing();string document=f.State.DocumentGeneration;
        if(!beforeStart)f.State.Command("reveal");
        lock(f.State.Gate)Check(f.State.RequestedReveal&&f.State.RevealEverRequested&&!f.State.Disabled,"early reveal is retained while preparation is pending");
        Check(f.Peer.Count("reveal")==0&&!f.State.WallpaperApplied,"reveal is not applied before preparation completes");
        Check(!PreparationWatchdog.Expire(f.State,120000)&&!f.State.Disabled,"early reveal retains wallpaper intent beyond old crash watchdog");
        f.Allow();Check(Until(()=>f.State.Ready&&f.State.Playing&&f.State.WallpaperApplied&&f.State.FirstFrameConfirmed,2500),"actual Run consumes early reveal after same-generation preparation");
        Check(f.State.DocumentGeneration==document&&f.Peer.Document==document&&f.State.MediaGeneration==1&&f.Peer.Generation==1,"prepared and revealed evidence belongs to one document and decoder");
        Check(f.Peer.Count("reveal")==1&&!f.State.RequestedReveal&&f.State.RevealEverRequested,"pending reveal is consumed exactly once");
        f.NoRepeatedMutations();f.Stop();Check(f.Failure==null&&f.Peer.Count("dispose")==1,"ordinary shutdown disposes one owned renderer");
        cases.Add(new{name=beforeStart?"reveal-before-host-prepare":"reveal-during-first-frame-prepare",passed=true});
    }}
    static void DisableCases(string directory){
        using(var f=new Fixture(directory)){
            f.State.Command("disable");f.State.Command("reveal");f.Start();Check(Until(()=>f.Ended,2000),"disable-before-reveal controller exits");
            Check(f.State.Disabled&&f.State.DesiredMode=="disabled"&&!f.State.RequestedReveal&&!f.State.RevealEverRequested,"early reveal never revives existing disable");
            Check(f.Peer.Count("media-attach")==0&&f.Peer.Count("reveal")==0&&f.Failure==null,"disabled startup performs no attachment or reveal");f.NoRepeatedMutations();
        }
        using(var f=new Fixture(directory)){
            f.Start();f.WaitPreparing();f.State.Command("reveal");f.State.Command("disable");f.State.Command("reveal");f.Allow();
            Check(Until(()=>f.Ended,2500),"disable-after-pending-reveal stops preparation");
            Check(f.State.Disabled&&f.State.DesiredMode=="disabled"&&!f.State.RequestedReveal&&!f.State.Ready&&!f.State.Playing,"later explicit disable wins over retained reveal");
            Check(f.Peer.Count("reveal")==0&&f.Peer.Count("dispose")==1&&f.Failure==null,"pending reveal never reaches renderer after disable");f.NoRepeatedMutations();
        }
        using(var f=new Fixture(directory)){
            f.State.Command("reveal");f.Peer.AllowPrepared=true;f.Start();Check(Until(()=>f.State.Playing,2500),"reveal is applied before explicit user disable fixture");
            f.State.Command("disable");f.State.Command("reveal");Check(Until(()=>f.Ended,2500),"disable after visible state stops controller");
            Check(f.State.Disabled&&f.State.DesiredMode=="disabled"&&f.Peer.Count("reveal")==1&&f.Peer.Count("dispose")==1,"late reveal cannot restart previously revealed then disabled renderer");f.NoRepeatedMutations();
        }
        cases.Add(new{name="disable-before-pending-and-completed-reveal-is-terminal",passed=true});
    }
    static void ContextInvalidation(string directory){
        foreach(string kind in new[]{"document","session","target","transport"})using(var f=new Fixture(directory)){
            bool changed=false;f.Peer.Before=request=>{
                if(changed||request.Kind!="status"||request.Phase!=10)return;changed=true;
                f.State.Command("reveal");
                if(kind=="document")Set(f.State,"DocumentGeneration",Guid.NewGuid().ToString("N"));
                else if(kind=="session")Set(f.Session,"session","replacement_session");
                else Set(f.Session,kind=="target"?"targetLost":"transportLost",true);
            };
            f.Start();Check(Until(()=>f.Ended,2500),"invalidated preparation ends within bound: "+kind);
            var failure=f.Failure as HostFailure;
            Check(changed&&failure!=null&&failure.Code==72&&f.State.Disabled,"invalidated context cannot become current evidence: "+kind);
            Check(f.Peer.Count("reveal")==0&&!f.State.Ready&&!f.State.Playing&&!f.State.WallpaperApplied,"invalidated generation never receives retained reveal: "+kind);f.NoRepeatedMutations();
        }
        cases.Add(new{name="pending-reveal-does-not-cross-document-session-or-target-loss",passed=true});
    }
    static void PreparationBound(string directory){using(var f=new Fixture(directory)){
        f.State.Command("reveal");var clock=Stopwatch.StartNew();f.Start();f.WaitPreparing();
        Check(Until(()=>f.Ended,10500),"permanently unready decoder cannot retain preparation indefinitely");
        var failure=f.Failure as HostFailure;
        Check(failure!=null&&failure.Code==68&&clock.ElapsedMilliseconds>=8000&&clock.ElapsedMilliseconds<12000,"existing 8.5 second first-frame preparation bound remains effective");
        Check(f.State.Disabled&&!f.State.Ready&&!f.State.Playing&&f.Peer.Count("reveal")==0,"a reveal request is not success and does not bypass preparation failure");f.NoRepeatedMutations();
        cases.Add(new{name="early-reveal-keeps-existing-first-frame-timeout",passed=true,elapsedMs=clock.ElapsedMilliseconds});
    }}
    static void ReadyBoundary(string directory){
        foreach(string kind in new[]{"disable","session","target","transport"})using(var f=new Fixture(directory)){
            bool changed=false;f.State.Command("reveal");f.Peer.AllowPrepared=true;
            f.Peer.Before=request=>{
                // Run has consumed its queued reveal and captured intent, but
                // still awaits the lease reply before mutating the renderer.
                if(changed||request.Kind!="renew"||request.Phase!=11)return;changed=true;
                if(kind=="disable")f.State.Command("disable");
                else if(kind=="session")Set(f.Session,"session","replacement_session");
                else Set(f.Session,kind=="target"?"targetLost":"transportLost",true);
            };
            f.Start();Check(Until(()=>f.Ended,2500),"ready-boundary change ends within bound: "+kind);
            var failure=f.Failure as HostFailure;
            Check(changed&&(kind=="disable"?f.Failure==null:failure!=null&&failure.Code==72),"fresh intent or context is checked after lease reply: "+kind);
            Check(f.State.Disabled&&!f.State.Ready&&!f.State.Playing&&!f.State.WallpaperApplied&&f.Peer.Count("reveal")==0,"captured reveal cannot outlive disable or target identity: "+kind);
            f.NoRepeatedMutations();
        }
        cases.Add(new{name="consumed-reveal-rechecks-disable-and-session-before-application",passed=true});
    }
    static int Main(string[] args){try{
        string directory=Path.GetFullPath(args[0]);Directory.CreateDirectory(directory);var watch=Stopwatch.StartNew();
        EarlyReveal(directory,true);EarlyReveal(directory,false);DisableCases(directory);ContextInvalidation(directory);ReadyBoundary(directory);PreparationBound(directory);
        Console.WriteLine(Json.Serializer().Serialize(new{passed=true,checks=checks,elapsedMs=watch.ElapsedMilliseconds,actualCodexStarted=false,nativeWindowsShown=false,mediaDecoded=false,realMemoryPressureCreated=false,realHostStateAndWallpaperSession=true,syntheticRendererPeer=true,cases=cases}));return 0;
    }catch(Exception error){Console.WriteLine("FAIL: "+error);return 1;}}
}
}
