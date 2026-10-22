using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Web.Script.Serialization;
namespace CodexDragonWallpaper {
internal static class RuntimeDiagnosticsTests {
    static int checks;
    static void Check(bool value,string name){if(!value)throw new Exception(name);checks++;}
    static string CaptureMemoryPressure(string state,long elapsed,long available,long total){
        Type type=typeof(PreparationDiagnostics);const BindingFlags flags=BindingFlags.Static|BindingFlags.NonPublic;
        var method=type.GetMethod("RecordMemoryPressure",flags);Check(method!=null,"missing recoverable memory-pressure diagnostics");
        object gate=type.GetField("writerGate",flags).GetValue(null);var busy=type.GetField("writerBusy",flags);
        var pending=(Queue<string>)type.GetField("pending",flags).GetValue(null);
        lock(gate){
            Check((int)busy.GetValue(null)==0&&pending.Count==0,"isolated diagnostic queue initially idle");busy.SetValue(null,1);
            try{method.Invoke(null,new object[]{state,elapsed,available,total});Check(pending.Count<=1,"one pressure transition emits at most one bounded record");return pending.Count==0?null:pending.Dequeue();}
            finally{pending.Clear();busy.SetValue(null,0);}
        }
    }
    static void MemoryPressureDiagnostics(){
        foreach(string state in new[]{"suspended","resume-requested"}){
            string line=CaptureMemoryPressure(state,31536000000L,536870911,34359738368);
            Check(line!=null&&line.Contains("phase=43")&&line.Contains("code=0")&&line.Contains("pressureState="+state),"recoverable pressure has a distinct fixed event");
            Check(line.Contains("availableCommitBytes=536870911")&&line.Contains("totalCommitBytes=34359738368"),"same-sample commit counters retained without resampling");
            Check(line.Length<=1024&&!line.Contains("174"),"pressure event remains bounded and is not legacy terminal failure");
        }
        string maximum=CaptureMemoryPressure("suspended",0,281474976710656L,281474976710656L);
        Check(maximum.Contains("availableCommitBytes=281474976710656")&&maximum.Contains("totalCommitBytes=281474976710656"),"commit counter maximum is bounded at 2^48");
        string unknown=CaptureMemoryPressure("suspended",0,-2,Int64.MaxValue);
        Check(unknown.Contains("availableCommitBytes=-1")&&unknown.Contains("totalCommitBytes=-1"),"invalid commit counters stay unknown");
        Check(CaptureMemoryPressure("PRIVATE_SENTINEL_KEY",0,1,2)==null,"arbitrary pressure string is never logged");
        Check(CaptureMemoryPressure("suspended",-1,1,2)==null&&CaptureMemoryPressure("suspended",31536000001L,1,2)==null,"invalid elapsed time is ignored without changing operation");
    }
    static Dictionary<string,object> Status(){return Json.Obj("attached",true,"mediaReady",true,"prepared",true,"disposed",false,"playing",true,"wallpaperApplied",true,"revealed",true,"layoutSupported",true,"firstFrameConfirmed",true,"documentHidden",false,"stageVisible",true,"recoveryNeeded",false,"leaseNeedsRenew",false,"layoutSuspended",false,"memoryPressure",false,"manuallyPaused",false,"videoPaused",false,"videoSeeking",false,"playStarted",true,"frameCallbackPending",false,"preparationTimerPending",false,"frozen",false,"videoReadyState",4,"videoErrorCode",0,"videoNetworkState",2,"mediaTimeMs",86400000,"mediaGeneration",Int32.MaxValue,"presentedFrames",Int32.MaxValue,"protocolVersion",2,"documentGeneration","PRIVATE_SENTINEL_GENERATION","code","recovery-budget-exhausted","actualPhase","visible","health","fresh","commitAccepted",true,"videoTotalFrames",Int32.MaxValue,"videoDroppedFrames",Int32.MaxValue,"videoCorruptedFrames",Int32.MaxValue,"videoWidth",16384,"videoHeight",16384);}
    static int Main(){try{
        var status=Status();status["layoutReason"]="composer-ambiguous";var before=new JavaScriptSerializer().Serialize(status);
        string line=PreparationDiagnostics.FormatRuntimeObservation(status,"PRIVATE_SENTINEL_GENERATION",31536000000L);
        Check(line.Contains("phase=39")&&line.Contains("commitAccepted=1"),"runtime state and commit");
        Check(line.Contains("layoutReason=composer-ambiguous"),"bounded layout reason");
        Check(PreparationDiagnostics.FormatReadinessObservation(6,1,status,"other").Contains("layoutReason=composer-ambiguous"),"preparation layout reason");
        Check(line.Length<=1024,"runtime line fits bounded sink: "+line.Length);
        Check(!line.Contains("PRIVATE_SENTINEL"),"document identity never logged");
        Check(line.Contains("generationMatches=1")&&line.Contains("firstFrameConfirmed=1"),"generation and first frame evidence");
        Check(new JavaScriptSerializer().Serialize(status)==before,"observations do not mutate state");
        string quality=PreparationDiagnostics.FormatPlaybackQuality(status,31536000000L);
        Check(quality.Contains("phase=40")&&quality.Contains("videoTotalFrames=2147483647")&&quality.Contains("videoWidth=16384"),"bounded quality maximums");
        Check(quality.Length<=1024&&!quality.Contains("PRIVATE_SENTINEL"),"quality sink and privacy");
        status["videoDroppedFrames"]=Double.NaN;status["videoTotalFrames"]=-1;status["videoCorruptedFrames"]=(long)Int32.MaxValue+1;status["videoWidth"]=16385;status.Remove("videoHeight");
        quality=PreparationDiagnostics.FormatPlaybackQuality(status,1);
        foreach(string key in new[]{"videoDroppedFrames","videoTotalFrames","videoCorruptedFrames","videoWidth","videoHeight"})Check(quality.Contains(key+"=-1"),"unknown "+key);
        status["code"]="PRIVATE_SENTINEL_CODE";status["health"]="PRIVATE_SENTINEL_HEALTH";status["actualPhase"]="PRIVATE_SENTINEL_PHASE";status["commitAccepted"]="true";status["layoutReason"]="PRIVATE_SENTINEL_LAYOUT";
        line=PreparationDiagnostics.FormatRuntimeObservation(status,"different",2);
        Check(!line.Contains("PRIVATE_SENTINEL")&&line.Contains("rendererCode=unknown")&&line.Contains("commitAccepted=-1"),"strict runtime fields");
        Check(line.Contains("generationMatches=0"),"wrong generation remains explicit");
        Check(line.Contains("layoutReason=unknown"),"unknown layout reason remains unknown");
        var stamps=new List<long>();var recorder=new RuntimeSnapshotRecorder((s,g,t)=>stamps.Add(t));status=Status();
        recorder.Observe(status,"generation",0);for(int i=1;i<2000;i++)recorder.Observe(status,"generation",i);
        Check(stamps.Count==1,"rapid queries do not flood log");
        status["commitAccepted"]=false;recorder.Observe(status,"generation",1999);recorder.Observe(status,"generation",2000);
        Check(stamps.Count==2&&stamps[1]==2000,"transition rate bounded at two seconds");
        recorder.Observe(status,"generation",31999);Check(stamps.Count==2,"steady period not shortened");
        recorder.Observe(status,"generation",32000);Check(stamps.Count==3,"thirty-second observation heartbeat");
        recorder.Observe(null,"generation",34000);recorder.Observe(status,"generation",-1);recorder.Observe(status,"generation",31536000001L);
        Check(stamps.Count==3,"invalid elapsed and null ignored");
        var throwing=new RuntimeSnapshotRecorder((s,g,t)=>{throw new InvalidOperationException();});throwing.Observe(status,"generation",0);
        Check(true,"diagnostic failure never changes operation");
        MemoryPressureDiagnostics();
        Console.WriteLine("{\"passed\":true,\"checks\":"+checks.ToString(CultureInfo.InvariantCulture)+",\"runtimeLineBytes\":"+line.Length+"}");return 0;
    }catch(Exception e){Console.WriteLine("{\"passed\":false,\"checks\":"+checks+",\"error\":"+new JavaScriptSerializer().Serialize(e.Message)+"}");return 1;}}
}}
