param([int]$TargetHost = 0)

$log = "$env:LOCALAPPDATA\InputSwitcher\switch_kb.log"
function Log($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    "$ts $msg" | Out-File -Append -FilePath $log -Encoding utf8
    Write-Host $msg
}

$src = @"
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Collections.Generic;
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
            foreach(var f in Directory.GetFiles(@"\\.\pipe\")) {
                string name = Path.GetFileName(f);
                if(name.StartsWith("logitech_kiros_agent-")) return name;
            }
        } catch {}
        return null;
    }
    static List<string> GetChangeHostIds(NamedPipeClientStream pipe, ref int mid) {
        var ids = new List<string>();
        string mId = (mid++).ToString();
        byte[] frame = Frame(mId, "GET", "/routes", null);
        pipe.Write(frame,0,frame.Length); pipe.Flush();
        string resp = ReadMsgWithId(pipe, mId) ?? "";
        int cur = 0;
        while ((cur = resp.IndexOf("/change_host/", cur)) >= 0) {
            int s = cur + "/change_host/".Length;
            int e = resp.IndexOf("/host", s);
            if (e > s) {
                string id = resp.Substring(s, e - s);
                if (!ids.Contains(id)) ids.Add(id);
            }
            cur = e > 0 ? e : cur + 1;
        }
        return ids;
    }
    // Switch ALL devices with canSetPlatform=true and multiple BLEPRO hosts.
    // Returns list of "id:result" strings.
    public static List<string> SwitchAllHosts(string pipeName, int host, out string debugInfo) {
        debugInfo = "";
        var results = new List<string>();
        var pipe=new NamedPipeClientStream(".",pipeName,PipeDirection.InOut,PipeOptions.None);
        try { pipe.Connect(3000); } catch { results.Add("NO_PIPE"); return results; }
        ReadMsg(pipe);
        int mid = 10;
        var changeHostIds = GetChangeHostIds(pipe, ref mid);
        debugInfo += "ids: " + string.Join(",", changeHostIds.ToArray()) + "; ";
        if (changeHostIds.Count == 0) { pipe.Close(); results.Add("NOT_CONNECTED"); return results; }
        foreach (var id in changeHostIds) {
            string mId = (mid++).ToString();
            byte[] frame = Frame(mId, "GET", "/devices/"+id+"/easy_switch", null);
            pipe.Write(frame,0,frame.Length); pipe.Flush();
            string r = ReadMsgWithId(pipe, mId) ?? "";
            bool hasPlatform = r.Contains("\"canSetPlatform\": true");
            int bleproCount = r.Split(new string[]{"\"busType\": \"BLEPRO\""}, StringSplitOptions.None).Length - 1;
            debugInfo += id+"(canSetPlatform="+hasPlatform+",BLEPRO="+bleproCount+"); ";
            if (!r.Contains("SUCCESS") || !hasPlatform || bleproCount <= 1) continue;
            // This device supports host switching — switch it
            string swId = (mid++).ToString();
            byte[] swFrame = Frame(swId, "SET", "/change_host/"+id+"/host", "{\"host\":"+host+"}");
            pipe.Write(swFrame,0,swFrame.Length); pipe.Flush();
            string resp2 = ReadMsgWithId(pipe, swId) ?? "";
            if (resp2.Contains("SUCCESS")) results.Add("OK:"+id);
            else if (resp2.Contains("NO_SUCH_PATH")) results.Add("NOT_CONNECTED:"+id);
            else results.Add("FAIL:"+id+":"+resp2.Substring(0, Math.Min(60, resp2.Length)));
        }
        pipe.Close();
        return results;
    }
}
"@

Add-Type -TypeDefinition $src -Language CSharp -ErrorAction SilentlyContinue 2>$null

Log "--- switch_kb.ps1 start, TargetHost=$TargetHost ---"

$pipeName = [KirosKeyboard]::FindPipeName()
if (-not $pipeName) {
    Log "K855: Logi Options+ agent pipe not found"
    exit 1
}
Log "pipe: $pipeName"

$debug = ""
$results = [KirosKeyboard]::SwitchAllHosts($pipeName, $TargetHost, [ref]$debug)
Log "debug: $debug"

if ($results.Count -eq 0) {
    Log "K855: no switchable devices found (NOT_FOUND)"
    exit 0
}

$anyOk = $false
foreach ($r in $results) {
    switch -Wildcard ($r) {
        "OK:*"           { Log "switched to host $TargetHost ($r)"; $anyOk = $true }
        "NOT_CONNECTED:*"{ Log "not connected ($r), skipped" }
        "NO_PIPE"        { Log "Logi Options+ pipe not available"; exit 1 }
        default          { Log "FAILED: $r" }
    }
}
if (-not $anyOk) { exit 1 }
