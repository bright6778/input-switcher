// Minimal native client bound to the hotkey instead of `powershell -File
// switch_kb.ps1`. It only opens the named pipe that switch_kb_service.ps1
// listens on, writes the target host, and exits — no PowerShell/AMSI
// scripting host involved, so this is not subject to the same EDR
// script-scan latency a fresh powershell.exe pays on every launch.
//
// Build (no project file needed, csc.exe ships with .NET Framework):
//   csc.exe /nologo /out:switch_trigger.exe switch_trigger.cs
//
// Usage:
//   switch_trigger.exe <targetHost 0-2>
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;

internal static class SwitchTrigger {
    private const string PipeName = "InputSwitcherService";
    private const int TimeoutMs = 4000;

    private static int Main(string[] args) {
        int targetHost;
        if (args.Length != 1 || !int.TryParse(args[0], out targetHost) ||
            targetHost < 0 || targetHost > 2) {
            Console.Error.WriteLine("usage: switch_trigger.exe <targetHost 0-2>");
            return 2;
        }

        try {
            using (var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut)) {
                pipe.Connect(TimeoutMs);
                pipe.ReadMode = PipeTransmissionMode.Byte;

                byte[] outBytes = Encoding.ASCII.GetBytes(targetHost.ToString() + "\n");
                pipe.Write(outBytes, 0, outBytes.Length);
                pipe.Flush();

                string response = ReadLine(pipe);
                if (response != null) Console.WriteLine(response);
                return (response != null && response.StartsWith("OK", StringComparison.Ordinal)) ? 0 : 1;
            }
        }
        catch (Exception ex) {
            Console.Error.WriteLine("switch_trigger: " + ex.Message +
                " (is switch_kb_service.ps1 running?)");
            return 1;
        }
    }

    // Reads one newline-terminated line directly off the pipe as raw bytes.
    // Avoids layering a StreamReader/StreamWriter on the same PipeStream,
    // which is a well-known source of buffering/dispose-order bugs.
    private static string ReadLine(Stream stream) {
        var bytes = new System.Collections.Generic.List<byte>();
        int b;
        while ((b = stream.ReadByte()) != -1) {
            if (b == '\n') break;
            if (b != '\r') bytes.Add((byte)b);
        }
        if (b == -1 && bytes.Count == 0) return null;
        return Encoding.ASCII.GetString(bytes.ToArray());
    }
}
