param(
    [ValidateRange(0, 2)]
    [int]$TargetHost = 0
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "InputSwitcher"
$log = Join-Path $stateDir "switch_kb.log"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

function Log($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    "$ts $msg" | Out-File -Append -FilePath $log -Encoding utf8
    Write-Host $msg
}

# Logi Options+ 2.7.961922 rejects direct named-pipe clients. The signed
# Options+ UI is still trusted, so start it briefly on a random loopback-only
# DevTools port and ask its existing preload API to send the switch request.
$cdpSource = @"
using System;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;

public static class InputSwitcherCdp {
    public static string Exchange(string webSocketUrl, string request, int expectedId, int timeoutMs) {
        using (var cts = new CancellationTokenSource())
        using (var socket = new ClientWebSocket()) {
            cts.CancelAfter(timeoutMs);
            socket.ConnectAsync(new Uri(webSocketUrl), cts.Token).GetAwaiter().GetResult();

            byte[] requestBytes = Encoding.UTF8.GetBytes(request);
            socket.SendAsync(
                new ArraySegment<byte>(requestBytes),
                WebSocketMessageType.Text,
                true,
                cts.Token
            ).GetAwaiter().GetResult();

            byte[] buffer = new byte[8192];
            string compactMarker = "\"id\":" + expectedId;
            string spacedMarker = "\"id\": " + expectedId;

            while (socket.State == WebSocketState.Open) {
                using (var message = new MemoryStream()) {
                    WebSocketReceiveResult received;
                    do {
                        received = socket.ReceiveAsync(
                            new ArraySegment<byte>(buffer),
                            cts.Token
                        ).GetAwaiter().GetResult();

                        if (received.MessageType == WebSocketMessageType.Close) {
                            throw new IOException("DevTools WebSocket closed before replying");
                        }
                        message.Write(buffer, 0, received.Count);
                    } while (!received.EndOfMessage);

                    string text = Encoding.UTF8.GetString(message.ToArray());
                    if (text.Contains(compactMarker) || text.Contains(spacedMarker)) {
                        return text;
                    }
                }
            }
        }
        throw new IOException("DevTools WebSocket closed before replying");
    }
}
"@

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Get-OptionsTarget($Port, [int]$TimeoutMs = 12000) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        try {
            $targets = @(Invoke-RestMethod `
                -Uri "http://127.0.0.1:$Port/json/list" `
                -TimeoutSec 1)
            $target = $targets | Where-Object {
                $_.type -eq "page" -and $_.url -match "LogiOptionsPlus.+index\.html"
            } | Select-Object -First 1
            if (-not $target) {
                $target = $targets | Where-Object { $_.type -eq "page" } |
                    Select-Object -First 1
            }
            if ($target.webSocketDebuggerUrl) {
                $version = Invoke-RestMethod `
                    -Uri "http://127.0.0.1:$Port/json/version" `
                    -TimeoutSec 1
                return [pscustomobject]@{
                    PageWebSocket = $target.webSocketDebuggerUrl
                    BrowserWebSocket = $version.webSocketDebuggerUrl
                }
            }
        }
        catch {
            # The UI is still starting. Retry until the short deadline.
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)

    return $null
}

function Invoke-CdpCommand($WebSocketUrl, $Method, $Parameters, [int]$TimeoutMs) {
    $request = @{
        id = 1
        method = $Method
        params = $Parameters
    } | ConvertTo-Json -Depth 8 -Compress

    $raw = [InputSwitcherCdp]::Exchange(
        $WebSocketUrl,
        $request,
        1,
        $TimeoutMs
    )
    return $raw | ConvertFrom-Json
}

$switchExpression = @'
(async () => {
  const targetHost = __TARGET_HOST__;
  const pending = new Map();
  let sequence = 0;

  window.electronNet.onMessage(message => {
    const id = String(message.msgId || message.msg_id || '');
    const complete = pending.get(id);
    if (complete) {
      pending.delete(id);
      complete(message);
    }
  });

  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

  // Establish a fresh trusted bridge instead of guessing when the UI's own
  // startup sequence has finished connecting to the agent.
  await new Promise(resolve => {
    let finished = false;
    const complete = () => {
      if (!finished) {
        finished = true;
        resolve();
      }
    };
    window.electronNet.onOpen(complete);
    window.electronNet.onError(complete);
    window.electronNet.createConnection();
    window.electronNet.connect();
    setTimeout(complete, 2000);
  });

  const request = (verb, path, payload) => new Promise(resolve => {
    const id = `input_switcher_${Date.now()}_${++sequence}`;
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve({ timeout: true, path });
    }, 2500);

    pending.set(id, response => {
      clearTimeout(timer);
      resolve(response);
    });

    const message = { msg_id: id, verb, path };
    if (payload !== undefined) message.payload = payload;
    window.electronNet.send(JSON.stringify(message));
  });

  // The page can appear just before its agent socket is ready. Retry routes.
  let routes = null;
  for (let attempt = 0; attempt < 4; attempt++) {
    routes = await request('GET', '/routes');
    if (routes && routes.result && routes.result.code === 'SUCCESS') break;
    await delay(400);
  }

  if (!routes || !routes.result || routes.result.code !== 'SUCCESS') {
    return {
      success: false,
      status: 'IPC_FAILED',
      detail: routes && routes.timeout ? 'routes timeout' : 'routes request failed'
    };
  }

  const ids = [...new Set((routes.payload && routes.payload.route || [])
    .map(route => {
      if (route.verb !== 'GET') return null;
      const match = /^\/change_host\/([^/]+)\/host$/.exec(route.path || '');
      return match ? match[1] : null;
    })
    .filter(Boolean))];

  const candidates = await Promise.all(ids.map(async id => {
    const [easySwitch, info] = await Promise.all([
      request('GET', `/devices/${id}/easy_switch`),
      request('GET', `/devices/${id}/info`)
    ]);

    const hosts = easySwitch && easySwitch.payload && easySwitch.payload.hosts || [];
    const capabilities = easySwitch && easySwitch.payload &&
      easySwitch.payload.capabilities || {};
    const device = info && info.payload || {};
    const eligible = easySwitch && easySwitch.result &&
      easySwitch.result.code === 'SUCCESS' &&
      info && info.result && info.result.code === 'SUCCESS' &&
      capabilities.canSetPlatform === true &&
      hosts.filter(host => host.paired && host.busType === 'BLEPRO').length > 1 &&
      device.deviceType === 'KEYBOARD' &&
      device.connected === true;

    return {
      id,
      name: device.displayName || device.extendedDisplayName || id,
      modelId: device.modelId || '',
      eligible
    };
  }));

  const keyboards = candidates.filter(candidate => candidate.eligible);
  if (keyboards.length === 0) {
    return { success: true, status: 'NOT_CONNECTED', candidates, switches: [] };
  }

  // The receiver can acknowledge concurrent SET requests while physically
  // applying only the first one. Send keyboard switches one at a time.
  const switches = [];
  for (const keyboard of keyboards) {
    const response = await request(
      'SET',
      `/change_host/${keyboard.id}/host`,
      { host: targetHost }
    );
    switches.push({
      id: keyboard.id,
      name: keyboard.name,
      code: response && response.result && response.result.code ||
        (response && response.timeout ? 'TIMEOUT' : 'FAILED')
    });
    await delay(250);
  }

  const success = switches.every(result => result.code === 'SUCCESS');
  return {
    success,
    status: success ? 'SWITCHED' : 'SWITCH_FAILED',
    candidates,
    switches
  };
})()
'@

Log "--- switch_kb.ps1 start, TargetHost=$TargetHost ---"

$mutex = $null
$mutexAcquired = $false
$launchedProcess = $null
$launchedByUs = $false
$targetInfo = $null
$exitCode = 1

try {
    Add-Type -TypeDefinition $cdpSource -Language CSharp -ErrorAction Stop

    $mutex = [System.Threading.Mutex]::new(
        $false,
        "Local\InputSwitcherKeyboardSwitch"
    )
    $mutexAcquired = $mutex.WaitOne(15000)
    if (-not $mutexAcquired) {
        throw "another keyboard switch is still running"
    }

    $optionsExe = Join-Path $env:ProgramFiles "LogiOptionsPlus\logioptionsplus.exe"
    if (-not (Test-Path -LiteralPath $optionsExe)) {
        throw "Logi Options+ UI was not found at $optionsExe"
    }

    $port = $null
    $existingMain = @(Get-CimInstance Win32_Process `
        -Filter "Name = 'logioptionsplus.exe'" | Where-Object {
            $_.CommandLine -notmatch "--type="
        }) | Select-Object -First 1

    if ($existingMain) {
        if ($existingMain.CommandLine -match "--remote-debugging-port=(\d+)") {
            $port = [int]$Matches[1]
            Log "using existing trusted Options+ UI (port $port)"
        }
        else {
            throw "Logi Options+ UI is already open without an automation port; close its window and retry"
        }
    }
    else {
        $port = Get-FreeLoopbackPort
        $launchedProcess = Start-Process `
            -FilePath $optionsExe `
            -ArgumentList @(
                "--remote-debugging-address=127.0.0.1",
                "--remote-debugging-port=$port",
                "--remote-allow-origins=*"
            ) `
            -WindowStyle Hidden `
            -PassThru
        $launchedByUs = $true
        Log "started trusted Options+ UI (pid $($launchedProcess.Id), port $port)"
    }

    $targetInfo = Get-OptionsTarget -Port $port
    if (-not $targetInfo) {
        throw "Options+ automation page did not become ready"
    }

    # The DevTools target is published slightly before preload and the
    # renderer's agent bridge finish initializing.
    Start-Sleep -Milliseconds 500

    $expression = $switchExpression.Replace(
        "__TARGET_HOST__",
        [string]$TargetHost
    )
    $result = $null
    $cdpResponse = $null
    for ($attempt = 1; $attempt -le 2 -and -not $result; $attempt++) {
        $cdpResponse = Invoke-CdpCommand `
            -WebSocketUrl $targetInfo.PageWebSocket `
            -Method "Runtime.evaluate" `
            -Parameters @{
                expression = $expression
                returnByValue = $true
                awaitPromise = $true
            } `
            -TimeoutMs 18000

        if ($cdpResponse.result.exceptionDetails) {
            throw "Options+ page error: $($cdpResponse.result.exceptionDetails.text)"
        }
        $result = $cdpResponse.result.result.value
        if (-not $result -and $attempt -lt 2) {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $result) {
        $inner = $cdpResponse.result.result
        throw "Options+ page returned no result (type=$($inner.type), description=$($inner.description))"
    }

    if ($result.candidates) {
        $candidateText = @($result.candidates | ForEach-Object {
            "$($_.name)[$($_.id),eligible=$($_.eligible)]"
        }) -join ", "
        Log "candidates: $candidateText"
    }

    if ($result.status -eq "NOT_CONNECTED") {
        Log "no connected switchable keyboard found; it may already be on the other PC"
        $exitCode = 0
    }
    elseif ($result.success) {
        foreach ($switched in @($result.switches)) {
            Log "switched $($switched.name) to host $TargetHost ($($switched.code))"
        }
        $exitCode = 0
    }
    else {
        throw "keyboard switch failed: $($result.status) $($result.detail)"
    }
}
catch {
    Log "FAILED: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    if ($launchedByUs -and $targetInfo -and $targetInfo.BrowserWebSocket) {
        try {
            Invoke-CdpCommand `
                -WebSocketUrl $targetInfo.BrowserWebSocket `
                -Method "Browser.close" `
                -Parameters @{} `
                -TimeoutMs 2000 | Out-Null
        }
        catch {
            # Browser.close commonly drops the socket before acknowledging it.
        }
    }

    if ($launchedByUs -and $launchedProcess) {
        try {
            if (-not $launchedProcess.WaitForExit(3000)) {
                Stop-Process -Id $launchedProcess.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Stop-Process -Id $launchedProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }

    if ($mutexAcquired -and $mutex) {
        $mutex.ReleaseMutex()
    }
    if ($mutex) {
        $mutex.Dispose()
    }
}

exit $exitCode
