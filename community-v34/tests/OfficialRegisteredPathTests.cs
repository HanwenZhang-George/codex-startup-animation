using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;
using CodexDragon.Official;

internal static class OfficialRegisteredPathTests {
    static int checks;
    static string fixtureRoot;
    static void Check(bool value,string label){checks++;if(!value)throw new Exception(label);}
    static void Reject(Action action,string label){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected,label);}
    static string Fixture(string relative){string path=Path.GetFullPath(Path.Combine(fixtureRoot,relative));if(!path.StartsWith(fixtureRoot+"\\",StringComparison.OrdinalIgnoreCase))throw new Exception("fixture path escaped");return path;}
    static string Package(string relative,string version){
        string root=Fixture(relative);Directory.CreateDirectory(Path.Combine(root,"app"));
        File.Copy(Assembly.GetExecutingAssembly().Location,Path.Combine(root,"app","ChatGPT.exe"),true);
        File.WriteAllText(Path.Combine(root,"AppxManifest.xml"),"<Package><Identity Name='OpenAI.Codex' ProcessorArchitecture='x64' Version='"+version+"'/><Applications><Application Id='App' Executable='app/ChatGPT.exe'/></Applications></Package>");return root;
    }
    static string FullName(string version){return "OpenAI.Codex_"+version+"_x64__2p2nqsd0c76g0";}
    // Creates only a fresh fixture directory or replaces the fixture alias's
    // own reparse data. No child traversal, recursive deletion or network I/O.
    static bool Junction(string link,string substitute,bool replace){
        if(!link.StartsWith(fixtureRoot+"\\",StringComparison.OrdinalIgnoreCase))throw new Exception("junction escaped fixture");
        if(!replace)Directory.CreateDirectory(link);
        using(var handle=CreateFile(link,0x40000000,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)){
            if(handle.IsInvalid)return false;
            byte[] text=Encoding.Unicode.GetBytes(substitute),data=new byte[16+text.Length+4];
            Array.Copy(BitConverter.GetBytes(0xA0000003U),0,data,0,4);Array.Copy(BitConverter.GetBytes((ushort)(data.Length-8)),0,data,4,2);
            Array.Copy(BitConverter.GetBytes((ushort)text.Length),0,data,10,2);Array.Copy(BitConverter.GetBytes((ushort)(text.Length+2)),0,data,12,2);Array.Copy(text,0,data,16,text.Length);
            uint returned;return DeviceIoControl(handle,0x000900A4,data,(uint)data.Length,IntPtr.Zero,0,out returned,IntPtr.Zero);
        }
    }
    static void WithPrefix(string target,string alias){Check(Junction(alias,@"\??\"+target,false),"fixture junction created");}
    static void Standard(string root){
        string name=FullName("26.1021.3705.0"),alias=Fixture("registered-alias");WithPrefix(root,alias);
        // R13's strict method is retained. This is the executable red baseline:
        // the same registered alias was rejected before R14's scoped resolver.
        Reject(()=>OfficialIdentityResolver.ReadPackage(name,alias),"R13 path rejects a linked registered root");
        var direct=OfficialIdentityResolver.ReadRegisteredPackage(name,root);
        var linked=OfficialIdentityResolver.ReadRegisteredPackage(name,alias);
        Check(linked.Root==direct.Root&&linked.Executable==direct.Executable,"registered alias uses exact physical manifest and executable");
        Check(OfficialIdentityResolver.ResolveRegisteredRootForProbe(alias)==root,"diagnostic bridge matches runtime root");
        Check(OfficialIdentityResolver.ResolveRegisteredRootForProbe(@"\\?\"+root)==root,"extended local DOS registration normalizes safely");
        string parent=Fixture("parent-alias");WithPrefix(Path.GetDirectoryName(root),parent);
        Check(OfficialIdentityResolver.ReadRegisteredPackage(name,Path.Combine(parent,Path.GetFileName(root))).Executable==direct.Executable,"registered root with linked ancestor resolves locally");
        using(var lease=new OfficialIdentityResolver.RegisteredRootLease(alias)){
            Check(lease.Path==root,"physical root lease retained");
            Check(!Junction(alias,@"\??\"+Fixture("other-package"),true),"alias retarget denied during root lease");
            Reject(()=>Directory.Move(alias,alias+"-moved"),"alias rename denied during root lease");
        }
        string next=Package("next-package","26.1022.1.0");
        Check(Junction(alias,@"\??\"+next,true),"fixture alias retarget allowed only after lease disposal");
        var updated=OfficialIdentityResolver.ReadRegisteredPackage(FullName("26.1022.1.0"),alias);
        Check(updated.Executable==Path.Combine(next,"app","ChatGPT.exe"),"new registered version reads newly resolved root");
        Reject(()=>OfficialIdentityResolver.ReadRegisteredPackage(name,alias),"old version cannot authorize retargeted new manifest");
    }
    static void Rejected(string root){
        foreach(string path in new[]{@"\\server.invalid\share\Codex",@"\\?\UNC\server.invalid\share",@"\\?\Volume{00000000-0000-0000-0000-000000000001}\Apps",@"\\.\C:\",@"\Device\HarddiskVolume1\Apps",@"\??\C:\Apps",@"C:relative",@"C:\Apps\..\other",@"C:\Apps\item:stream"})
            Reject(()=>OfficialIdentityResolver.ResolveRegisteredRootForProbe(path),"nonlocal/device/noncanonical root rejected before I/O");
        string remote=Fixture("remote-alias");Check(Junction(remote,@"\??\UNC\server.invalid\share",false),"nonlocal fixture link created without following it");
        var watch=Stopwatch.StartNew();Reject(()=>OfficialIdentityResolver.ResolveRegisteredRootForProbe(remote),"remote junction target rejected without resolving network");Check(watch.ElapsedMilliseconds<2000,"remote rejection bounded without network connection");
        string loop=Fixture("loop-alias");WithPrefix(loop,loop);Reject(()=>OfficialIdentityResolver.ResolveRegisteredRootForProbe(loop),"self-loop alias rejected within finite budget");
        string missing=Fixture("missing-alias");WithPrefix(Fixture("does-not-exist"),missing);Reject(()=>OfficialIdentityResolver.ResolveRegisteredRootForProbe(missing),"missing local target rejected");
        string child=Package("child-link-package","26.1021.3705.0"),outside=Package("outside-package","26.1021.3705.0");
        WithPrefix(Path.Combine(outside,"app"),Path.Combine(child,"linked"));
        File.WriteAllText(Path.Combine(child,"AppxManifest.xml"),"<Package><Identity Name='OpenAI.Codex' ProcessorArchitecture='x64' Version='26.1021.3705.0'/><Applications><Application Id='App' Executable='linked/ChatGPT.exe'/></Applications></Package>");
        Reject(()=>OfficialIdentityResolver.ReadRegisteredPackage(FullName("26.1021.3705.0"),child),"child executable link outside package remains rejected");
        string remoteChild=Package("child-remote-package","26.1021.3705.0");
        Check(Junction(Path.Combine(remoteChild,"linked"),@"\??\UNC\server.invalid\share",false),"remote child fixture created without contact");
        File.WriteAllText(Path.Combine(remoteChild,"AppxManifest.xml"),"<Package><Identity Name='OpenAI.Codex' ProcessorArchitecture='x64' Version='26.1021.3705.0'/><Applications><Application Id='App' Executable='linked/ChatGPT.exe'/></Applications></Package>");
        watch.Restart();Reject(()=>OfficialIdentityResolver.ReadRegisteredPackage(FullName("26.1021.3705.0"),remoteChild),"remote executable child link rejected before leaf probing");Check(watch.ElapsedMilliseconds<2000,"child rejection does not wait for remote target");
        var package=OfficialIdentityResolver.ReadRegisteredPackage(FullName("26.1021.3705.0"),root);
        var acquire=typeof(OfficialIdentityResolver).GetMethod("Acquire",BindingFlags.Static|BindingFlags.NonPublic);
        bool denied=false;try{acquire.Invoke(null,new object[]{package});}catch(TargetInvocationException error){denied=OfficialIdentityResolver.DiagnosticCode(error.InnerException)==12;}
        Check(denied,"unsigned fixture still fails actual WinVerifyTrust identity acquisition");
    }
    static byte[] LinkData(uint tag,string substitute,uint flags){
        int start=tag==0xA000000C?20:16;byte[] text=Encoding.Unicode.GetBytes(substitute),data=new byte[start+text.Length+4];
        Array.Copy(BitConverter.GetBytes(tag),0,data,0,4);Array.Copy(BitConverter.GetBytes((ushort)(data.Length-8)),0,data,4,2);
        Array.Copy(BitConverter.GetBytes((ushort)text.Length),0,data,10,2);Array.Copy(BitConverter.GetBytes((ushort)(text.Length+2)),0,data,12,2);
        if(tag==0xA000000C)Array.Copy(BitConverter.GetBytes(flags),0,data,16,4);Array.Copy(text,0,data,start,text.Length);return data;
    }
    static void LinkParser(string root){
        string prefix=Fixture("parser-link");uint symlink=0xA000000C,junction=0xA0000003;
        byte[] data=LinkData(symlink,@"\??\"+root,0);
        Check(OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(symlink,data,data.Length,prefix)==root,"absolute directory symlink decodes to local target");
        data=LinkData(symlink,"physical-package",1);
        Check(OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(symlink,data,data.Length,prefix)==root,"relative directory symlink canonicalizes locally");
        foreach(string unsafePath in new[]{@"\??\UNC\server.invalid\share",@"\\server.invalid\share",@"\??\Volume{00000000-0000-0000-0000-000000000001}\",@"\Device\HarddiskVolume1\App"}){
            data=LinkData(symlink,unsafePath,0);byte[] captured=data;Reject(()=>OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(symlink,captured,captured.Length,prefix),"symlink nonlocal/unsupported target rejected before open");
        }
        data=LinkData(symlink,root,3);byte[] badFlags=data;Reject(()=>OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(symlink,badFlags,badFlags.Length,prefix),"unknown symlink flags rejected");
        data=LinkData(junction,@"\??\"+root,0);byte[] truncated=data;Reject(()=>OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(junction,truncated,10,prefix),"truncated reparse metadata rejected");
        data=LinkData(junction,@"\??\"+root,0);data[8]=1;byte[] unaligned=data;Reject(()=>OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(junction,unaligned,unaligned.Length,prefix),"unaligned substitute offset rejected");
        foreach(uint tag in new[]{0x9000001AU,0x80000017U,0x8000001BU,0xDEADBEEFU})Reject(()=>OfficialIdentityResolver.RegisteredRootLease.ParseLocalLink(tag,null,0,prefix),"cloud/compression/unknown tag cannot become local alias");
    }
    static void ProcessImage(string root){
        string alias=Fixture("process-alias");WithPrefix(root,alias);
        using(var process=Process.Start(new ProcessStartInfo{FileName=Path.Combine(alias,"app","ChatGPT.exe"),Arguments="--fixture-child",UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=fixtureRoot})){
            var path=new StringBuilder(4096);uint length=(uint)path.Capacity;
            Check(QueryFullProcessImageName(process.Handle,0,path,ref length),"synthetic process image queried");
            Check(String.Equals(path.ToString(),Path.Combine(root,"app","ChatGPT.exe"),StringComparison.OrdinalIgnoreCase),"Windows process image is physical after junction launch");
            Check(process.WaitForExit(5000)&&process.ExitCode==0,"synthetic child exits without affecting any app");
        }
    }
    static int Main(string[] args){try{
        if(args.Length==1&&args[0]=="--fixture-child"){Thread.Sleep(1500);return 0;}
        if(args.Length!=1)return 2;fixtureRoot=Path.GetFullPath(args[0]);Directory.CreateDirectory(fixtureRoot);
        Check(fixtureRoot==Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"fixtures"),"all fixture writes constrained to fresh output");
        string root=Package("physical-package","26.1021.3705.0");Standard(root);Rejected(root);LinkParser(root);ProcessImage(root);
        foreach(string code in new[]{"official-registered-root-invalid","official-registered-root-target-unsupported","official-path-access-denied","official-path-metadata-unavailable","official-registered-root-link-limit"})Check(OfficialIdentityResolver.DiagnosticCode(new InvalidOperationException(code))==11,"new path failures retain identity category");
        Check(OfficialIdentityResolver.DiagnosticReason(new UnauthorizedAccessException("private path"))=="path-access-denied","access error sanitized");
        Check(OfficialIdentityResolver.DiagnosticReason(new InvalidOperationException("private secret"))=="unknown","arbitrary text never exported");
        Console.WriteLine("{\"passed\":true,\"checks\":"+checks+",\"realCodexStarted\":false,\"syntheticChildOnly\":true,\"redBaselineRejected\":true}");return 0;
    }catch(Exception error){Console.WriteLine("FAIL "+error.GetType().Name+" "+error.Message);return 1;}}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool DeviceIoControl(SafeFileHandle handle,uint control,byte[] input,uint inputBytes,IntPtr output,uint outputBytes,out uint returned,IntPtr overlapped);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder image,ref uint size);
}
