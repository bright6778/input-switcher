param([int]$TargetHost = 0)

$src = @"
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
public class KirosKeyboard {
    static byte[] Frame(string msgId, string verb, string path, string payload) {
        string json = "{" + "\"msg_id\":\""+msgId+"\",\"verb\":\""+verb+"\",\"path\":\""+path+"\"" +
            (string.IsNullOrEmpty(payload) ? "" : ",\"payload\":"+payload) + "}";
        byte[] j=Encoding.UTF8.GetBytes(json); byte[] p=Encoding.UTF8.GetBytes("json");
        int olen=p.Length+j.Length+8; byte[] f=new byte[4+4+p.Length+4+j.Length]; int pos=0;
        f[pos++]=(byte)(olen&0xFF); f[pos++]=(byte)((olen>>8)&0xFF); f[pos++]=(byte)((olen>>16)&0xFF); f[pos++]=(byte)((olen>>24)&0xFF);
        f[pos++]=0; f[pos++]=0; f[pos++]=0; f[pos++]=(byte)p.Length;
        Array.Copy(p,0,f,pos,p.Length); pos+=p.Length;
        f[pos++]=(byte)((j.Length>>24)&0xFF); f[pos++]=(byte)((j.Length>>16)&0xFF); f[pos++]=(byte)((j.Length>>8)&0xFF); f[pos++]=(byte)(j.Length&0xFF);
        Array.Copy(j,0,f,pos,j.Length); return f;
    }
    static byte[] ReadFull(NamedPipeClientStream pipe, int n) {
        byte[] buf=new byte[n]; int got=0;
        while(got<n){byte[] tmp=new byte[n-got]; int read=0;
            var t=new Thread(()=>{try{read=pipe.Read(tmp,0,tmp.Length);}catch{}});
            t.Start(); t.Join(4000); if(read==0) return null;
            Array.Copy(tmp,0,buf,got,read); got+=read;} return buf;
    }
    static string ReadMsg(NamedPipeClientStream pipe) {
        var b=ReadFull(pipe,4); if(b==null) return null;
        b=ReadFull(pipe,4); if(b==null) return null;
        int plen=(b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]; b=ReadFull(pipe,plen); if(b==null) return null;
        b=ReadFull(pipe,4); if(b==null) return null;
        int dlen=(b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]; b=ReadFull(pipe,dlen); if(b==null) return null;
        return Encoding.UTF8.GetString(b);
    }
    static string ReadMsgWithId(NamedPipeClientStream pipe, string expectedId) {
        for(int attempt=0; attempt<6; attempt++) {
            string r = ReadMsg(pipe);
            if(r==null) return null;
            if(r.Contains("\"msgId\": \""+expectedId+"\"")) return r;
        }
        return null;
    }
    public static string FindPipeName() {
        try {
            string pipeDir = @"\\.\pipe\";
            foreach(var f in Directory.GetFiles(pipeDir)) {
                string name = Path.GetFileName(f);
                if(name.StartsWith("logitech_kiros_agent-")) return name;
            }
        } catch {}
        return null;
    }
    public static string SwitchKeyboardHost(string pipeName, int host) {
        var pipe=new NamedPipeClientStream(".",pipeName,PipeDirection.InOut,PipeOptions.None);
        try { pipe.Connect(3000); } catch { return "NO_PIPE"; }
        ReadMsg(pipe);
        string[] candidates = {"dev00000001","dev00000002","dev00000003","dev00000004",
                               "dev00000005","dev00000006","dev00000007","dev00000008",
                               "dev0000000a","dev0000000b","dev0000000c","dev0000000d"};
        string keyboardId = null;
        int mid = 10;
        foreach (var id in candidates) {
            string mId = (mid++).ToString();
            byte[] frame=Frame(mId,"GET","/devices/"+id+"/easy_switch",null);
            pipe.Write(frame,0,frame.Length); pipe.Flush();
            string r = ReadMsgWithId(pipe, mId) ?? "";
            if (r.Contains("SUCCESS") && r.Contains("\"canSetPlatform\": true") &&
                r.Split(new string[]{"\"busType\": \"BLEPRO\""}, StringSplitOptions.None).Length > 2) {
                keyboardId = id;
                break;
            }
        }
        if (keyboardId == null) { pipe.Close(); return "NOT_FOUND"; }
        string swId = (mid++).ToString();
        byte[] swFrame=Frame(swId,"SET","/change_host/"+keyboardId+"/host","{\"host\":"+host+"}");
        pipe.Write(swFrame,0,swFrame.Length); pipe.Flush();
        string resp = ReadMsgWithId(pipe, swId) ?? "";
        pipe.Close();
        if (resp.Contains("SUCCESS")) return "OK:"+keyboardId;
        if (resp.Contains("NO_SUCH_PATH")) return "NOT_CONNECTED";
        return "FAIL";
    }
}
"@

Add-Type -TypeDefinition $src -Language CSharp -ErrorAction SilentlyContinue 2>$null

$pipeName = [KirosKeyboard]::FindPipeName()
if (-not $pipeName) {
    Write-Host "K855: Logi Options+ agent pipe not found"
    exit 1
}

$r = [KirosKeyboard]::SwitchKeyboardHost($pipeName, $TargetHost)
switch -Wildcard ($r) {
    "OK:*"         { Write-Host "K855: switched to host $TargetHost" }
    "NOT_CONNECTED" { Write-Host "K855: not connected to this PC (already switched?)"; exit 0 }
    "NOT_FOUND"    { Write-Host "K855: keyboard not found on this PC"; exit 0 }
    default        { Write-Host "K855: FAILED ($r)"; exit 1 }
}