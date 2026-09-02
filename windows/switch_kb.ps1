param(
    [ValidateRange(0, 2)]
    [int]$TargetHost = 0
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "InputSwitcher"
$log = Join-Path $stateDir "switch_kb.log"
$cachePath = Join-Path $stateDir "keyboard_devices.json"
$bridgeStatePath = Join-Path $stateDir "options_bridge.json"
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Log($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    "$ts $msg" | Out-File -Append -FilePath $log -Encoding utf8
    Write-Host $msg
}

function Write-Utf8IfChanged($Path, $Content) {
    if (Test-Path -LiteralPath $Path) {
        try {
            if ((Get-Content -LiteralPath $Path -Raw) -eq $Content) {
                return
            }
        }
        catch {
            # Replace an unreadable state file with the verified state below.
        }
    }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# Logi Options+ 2.7.961922 rejects direct named-pipe clients. The signed UI is
# still trusted, so keep one minimized UI process available as a fast bridge.

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

function Get-OptionsTarget($Port, [int]$TimeoutMs = 10000) {
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
                return $target.webSocketDebuggerUrl
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

    $cts = [System.Threading.CancellationTokenSource]::new()
    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $cts.CancelAfter($TimeoutMs)
        $socket.ConnectAsync(
            [Uri]$WebSocketUrl,
            $cts.Token
        ).GetAwaiter().GetResult()

        [byte[]]$requestBytes = [Text.Encoding]::UTF8.GetBytes($request)
        $socket.SendAsync(
            [ArraySegment[byte]]::new($requestBytes),
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $cts.Token
        ).GetAwaiter().GetResult()

        [byte[]]$buffer = New-Object byte[] 8192
        while ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $message = [IO.MemoryStream]::new()
            try {
                do {
                    $received = $socket.ReceiveAsync(
                        [ArraySegment[byte]]::new($buffer),
                        $cts.Token
                    ).GetAwaiter().GetResult()
                    if ($received.MessageType -eq `
                        [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        throw "DevTools WebSocket closed before replying"
                    }
                    $message.Write($buffer, 0, $received.Count)
                } while (-not $received.EndOfMessage)

                $raw = [Text.Encoding]::UTF8.GetString($message.ToArray())
                if ($raw -match '"id"\s*:\s*1(?:,|})') {
                    return $raw | ConvertFrom-Json
                }
            }
            finally {
                $message.Dispose()
            }
        }
        throw "DevTools WebSocket closed before replying"
    }
    finally {
        $socket.Dispose()
        $cts.Dispose()
    }
}

$switchExpression = @'
(async () => {
  const started = performance.now();
  const targetHost = __TARGET_HOST__;
  const cachedDevices = __CACHED_DEVICES__;
  const initializeBridge = __INITIALIZE_BRIDGE__;

  // The renderer stays alive between switches. Install exactly one set of
  // preload listeners so repeated hotkey presses do not leak callbacks.
  if (!window.__inputSwitcherBridge) {
    const state = {
      pending: new Map(),
      sequence: 0,
      connectionState: 'unknown',
      connectWaiters: []
    };
    window.electronNet.onMessage(message => {
      const id = String(message.msgId || message.msg_id || '');
      const complete = state.pending.get(id);
      if (complete) {
        state.pending.delete(id);
        complete(message);
      }
    });
    window.electronNet.onOpen(() => {
      state.connectionState = 'open';
      const waiters = state.connectWaiters.splice(0);
      waiters.forEach(complete => complete());
    });
    window.electronNet.onError(() => {
      state.connectionState = 'error';
    });
    window.electronNet.onClose(() => {
      state.connectionState = 'closed';
    });
    window.__inputSwitcherBridge = state;
  }
  const bridge = window.__inputSwitcherBridge;

  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const request = (verb, path, payload, timeoutMs = 700) => new Promise(resolve => {
    const id = `input_switcher_${Date.now()}_${++bridge.sequence}`;
    const timer = setTimeout(() => {
      bridge.pending.delete(id);
      resolve({ timeout: true, path });
    }, timeoutMs);

    bridge.pending.set(id, response => {
      clearTimeout(timer);
      resolve(response);
    });

    const message = { msg_id: id, verb, path };
    if (payload !== undefined) message.payload = payload;
    window.electronNet.send(JSON.stringify(message));
  });

  const requestWithRetry = async (
    verb,
    path,
    payload,
    attempts = 2,
    timeoutMs = 700
  ) => {
    let response = null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      response = await request(verb, path, payload, timeoutMs);
      if (!response.timeout) return response;
      await delay(80);
    }
    return response;
  };

  const connectBridge = () => new Promise(resolve => {
    if (bridge.connectionState === 'open') {
      resolve();
      return;
    }
    let finished = false;
    let timer = null;
    const complete = () => {
      if (!finished) {
        finished = true;
        if (timer !== null) clearTimeout(timer);
        const index = bridge.connectWaiters.indexOf(complete);
        if (index >= 0) bridge.connectWaiters.splice(index, 1);
        resolve();
      }
    };
    bridge.connectWaiters.push(complete);
    window.electronNet.createConnection();
    window.electronNet.connect();
    timer = setTimeout(complete, 1500);
  });

  if (initializeBridge) {
    // Let the renderer finish its own startup before replacing its agent
    // connection. This cost is paid only after login/Options+ restart.
    await delay(1200);
    await connectBridge();
  }

  const isSuccess = response => response && response.result &&
    response.result.code === 'SUCCESS';

  const checkCachedDevices = async () => Promise.all(cachedDevices.map(async cached => {
    const info = await requestWithRetry(
      'GET',
      `/devices/${cached.id}/info`,
      undefined,
      initializeBridge ? 3 : 2,
      550
    );
    const device = info && info.payload || {};
    const reachable = Boolean(info && !info.timeout);
    const identityMatches = isSuccess(info) &&
      device.deviceType === 'KEYBOARD' &&
      device.modelId === cached.modelId;
    return {
      id: cached.id,
      name: device.displayName || cached.name || cached.id,
      modelId: cached.modelId,
      connected: identityMatches && device.connected === true,
      reachable,
      // Exact type/model validation makes the cache safe across agent restarts
      // without another Windows process query on every hotkey press.
      valid: identityMatches
    };
  }));

  let candidates = [];
  let source = 'cache';
  if (cachedDevices.length > 0) {
    candidates = await checkCachedDevices();
    if (candidates.every(candidate => !candidate.reachable)) {
      // Recover a bridge that was overwritten during UI startup/restart.
      await delay(250);
      await connectBridge();
      candidates = await checkCachedDevices();
    }
  }

  if (cachedDevices.length === 0 || candidates.some(candidate => !candidate.valid)) {
    source = 'discovery';
    let routes = await requestWithRetry(
      'GET',
      '/routes',
      undefined,
      3,
      1600
    );
    if (!isSuccess(routes) && initializeBridge) {
      await connectBridge();
      routes = await requestWithRetry('GET', '/routes', undefined, 2, 1600);
    }
    if (!isSuccess(routes)) {
      return {
        success: false,
        status: 'IPC_FAILED',
        detail: 'routes request failed',
        elapsedMs: Math.round(performance.now() - started)
      };
    }

    const ids = [...new Set((routes.payload && routes.payload.route || [])
      .map(route => {
        if (route.verb !== 'GET') return null;
        const match = /^\/change_host\/([^/]+)\/host$/.exec(route.path || '');
        return match ? match[1] : null;
      })
      .filter(Boolean))];

    const infos = await Promise.all(ids.map(async id => ({
      id,
      response: await requestWithRetry(
        'GET',
        `/devices/${id}/info`,
        undefined,
        2,
        700
      )
    })));
    const keyboards = infos.filter(item => isSuccess(item.response) &&
      item.response.payload && item.response.payload.deviceType === 'KEYBOARD');

    candidates = await Promise.all(keyboards.map(async item => {
      const easySwitch = await requestWithRetry(
        'GET',
        `/devices/${item.id}/easy_switch`,
        undefined,
        2,
        700
      );
      const device = item.response.payload || {};
      const hosts = easySwitch && easySwitch.payload && easySwitch.payload.hosts || [];
      const capabilities = easySwitch && easySwitch.payload &&
        easySwitch.payload.capabilities || {};
      const valid = isSuccess(easySwitch) &&
        capabilities.canSetPlatform === true &&
        hosts.filter(host => host.paired && host.busType === 'BLEPRO').length > 1;
      return {
        id: item.id,
        name: device.displayName || device.extendedDisplayName || item.id,
        modelId: device.modelId || '',
        connected: device.connected === true,
        valid
      };
    }));
  }

  const cache = candidates.filter(candidate => candidate.valid).map(candidate => ({
    id: candidate.id,
    name: candidate.name,
    modelId: candidate.modelId
  }));
  const keyboards = candidates.filter(candidate => candidate.valid && candidate.connected);
  if (keyboards.length === 0) {
    return {
      success: true,
      status: 'NOT_CONNECTED',
      source,
      cache,
      candidates,
      switches: [],
      elapsedMs: Math.round(performance.now() - started)
    };
  }

  const switches = [];
  for (const keyboard of keyboards) {
    const response = await requestWithRetry(
      'SET',
      `/change_host/${keyboard.id}/host`,
      { host: targetHost },
      2,
      1200
    );
    switches.push({
      id: keyboard.id,
      name: keyboard.name,
      code: response && response.result && response.result.code ||
        (response && response.timeout ? 'TIMEOUT' : 'FAILED')
    });
    await delay(100);
  }

  const success = switches.every(result => result.code === 'SUCCESS');
  return {
    success,
    status: success ? 'SWITCHED' : 'SWITCH_FAILED',
    source,
    cache,
    candidates,
    switches,
    elapsedMs: Math.round(performance.now() - started)
  };
})()
'@

$mutex = $null
$mutexAcquired = $false
$launchedProcess = $null
$launchedByUs = $false
$bridgeReady = $false
$bridgeStateText = $null
$exitCode = 1

try {
    $mutex = [System.Threading.Mutex]::new(
        $false,
        "Local\InputSwitcherKeyboardSwitch"
    )
    $mutexAcquired = $mutex.WaitOne(15000)
    if (-not $mutexAcquired) {
        throw "another keyboard switch is still running"
    }

    $optionsExe = Join-Path $env:ProgramFiles "LogiOptionsPlus\logioptionsplus.exe"

    $port = $null
    $targetInfo = $null
    $bridgePid = $null
    $bridgeStartTicks = $null
    if (Test-Path -LiteralPath $bridgeStatePath) {
        try {
            $bridgeStateText = Get-Content -LiteralPath $bridgeStatePath -Raw
            $bridgeState = $bridgeStateText | ConvertFrom-Json
            $bridgeProcess = Get-Process -Id $bridgeState.pid -ErrorAction Stop
            if ($bridgeProcess.ProcessName -eq "logioptionsplus") {
                $bridgeStartTicks = $bridgeProcess.StartTime.ToUniversalTime().Ticks
                if (($bridgeState.PSObject.Properties.Name -contains "startedTicks") -and
                    [long]$bridgeState.startedTicks -ne $bridgeStartTicks) {
                    throw "cached bridge PID was reused"
                }
                $port = [int]$bridgeState.port
                if ($bridgeState.PSObject.Properties.Name -contains "targetWebSocket") {
                    $targetInfo = [string]$bridgeState.targetWebSocket
                }
                if (-not $targetInfo) {
                    $targetInfo = Get-OptionsTarget -Port $port -TimeoutMs 400
                }
                if ($targetInfo) {
                    $bridgePid = $bridgeProcess.Id
                }
            }
        }
        catch {
            $targetInfo = $null
        }
    }

    if (-not $targetInfo) {
        $existingMains = @(Get-CimInstance Win32_Process `
            -Filter "Name = 'logioptionsplus.exe'" | Where-Object {
                $_.CommandLine -notmatch "--type="
            })
        $existingMain = $existingMains | Where-Object {
            $_.CommandLine -match "--remote-debugging-port=\d+"
        } | Select-Object -First 1

        if ($existingMain) {
            if ($existingMain.CommandLine -match "--remote-debugging-port=(\d+)") {
                $port = [int]$Matches[1]
                $bridgePid = $existingMain.ProcessId
                $bridgeProcess = Get-Process -Id $bridgePid -ErrorAction Stop
                $bridgeStartTicks = $bridgeProcess.StartTime.ToUniversalTime().Ticks
            }
        }
        elseif ($existingMains.Count -gt 0) {
            throw "Logi Options+ UI is already open without an automation port; close its window and retry"
        }
        else {
            if (-not (Test-Path -LiteralPath $optionsExe)) {
                throw "Logi Options+ UI was not found at $optionsExe"
            }
            $port = Get-FreeLoopbackPort
            # Launch via WMI (not Start-Process) so the UI is parented by the
            # WMI provider host instead of the calling console's process tree.
            # Terminals such as Windows Terminal put everything they spawn
            # into a Job Object that kills all descendants when the tab
            # closes; a WMI-created process sits outside that tree entirely,
            # so closing the console no longer takes Options+ down with it.
            $startupInfo = New-CimInstance -ClassName Win32_ProcessStartup `
                -ClientOnly -Property @{ ShowWindow = [uint16]7 } # SW_SHOWMINNOACTIVE
            $commandLine = '"{0}" --remote-debugging-address=127.0.0.1 --remote-debugging-port={1} --remote-allow-origins=*' -f $optionsExe, $port
            $createResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
                CommandLine = $commandLine
                ProcessStartupInformation = $startupInfo
            }
            if ($createResult.ReturnValue -ne 0) {
                throw "failed to launch Options+ UI via WMI (code $($createResult.ReturnValue))"
            }
            $launchedProcess = Get-Process -Id $createResult.ProcessId
            $bridgePid = $launchedProcess.Id
            $bridgeStartTicks = $launchedProcess.StartTime.ToUniversalTime().Ticks
            $launchedByUs = $true
            Log "started trusted Options+ UI via WMI (pid $bridgePid, port $port)"
        }

        $targetInfo = Get-OptionsTarget -Port $port
    }
    if (-not $targetInfo) {
        throw "Options+ automation page did not become ready"
    }

    $cachedDevices = @()
    if (Test-Path -LiteralPath $cachePath) {
        try {
            $cacheDocument = Get-Content -LiteralPath $cachePath -Raw |
                ConvertFrom-Json
            if ($cacheDocument.PSObject.Properties.Name -contains "devices") {
                $cachedDevices = @($cacheDocument.devices)
            }
        }
        catch {
            Log "ignoring invalid keyboard cache"
        }
    }
    $cachedJson = if ($cachedDevices.Count -gt 0) {
        ConvertTo-Json -InputObject @($cachedDevices) -Depth 4 -Compress
    }
    else {
        "[]"
    }

    $expression = $switchExpression.Replace(
        "__TARGET_HOST__", [string]$TargetHost
    ).Replace(
        "__CACHED_DEVICES__", $cachedJson
    ).Replace(
        "__INITIALIZE_BRIDGE__", $(if ($launchedByUs) { "true" } else { "false" })
    )
    $result = $null
    $cdpResponse = $null
    for ($attempt = 1; $attempt -le 2 -and -not $result; $attempt++) {
        try {
            $cdpResponse = Invoke-CdpCommand `
                -WebSocketUrl $targetInfo `
                -Method "Runtime.evaluate" `
                -Parameters @{
                    expression = $expression
                    returnByValue = $true
                    awaitPromise = $true
                } `
                -TimeoutMs 18000
        }
        catch {
            if ($attempt -lt 2) {
                $refreshedTarget = Get-OptionsTarget -Port $port -TimeoutMs 1200
                if ($refreshedTarget) {
                    $targetInfo = $refreshedTarget
                    continue
                }
            }
            throw
        }

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

    $bridgeReady = $result.status -ne "IPC_FAILED"
    if ($bridgeReady) {
        $newBridgeStateText = ConvertTo-Json -InputObject ([pscustomobject]@{
            pid = $bridgePid
            startedTicks = $bridgeStartTicks
            port = $port
            targetWebSocket = $targetInfo
        }) -Compress
        if ($bridgeStateText -ne $newBridgeStateText) {
            Write-Utf8IfChanged -Path $bridgeStatePath -Content $newBridgeStateText
            $bridgeStateText = $newBridgeStateText
        }
    }

    if ($bridgeReady -and $launchedByUs) {
        try {
            # Minimize through the app's own preload API first so a later
            # normal Options+ launch can restore the window correctly.
            Invoke-CdpCommand `
                -WebSocketUrl $targetInfo `
                -Method "Runtime.evaluate" `
                -Parameters @{
                    expression = "window.electronSend.minimizeWindow(); true"
                    returnByValue = $true
                } `
                -TimeoutMs 2000 | Out-Null
            Start-Sleep -Milliseconds 250

            # Remove the minimized taskbar button while preserving Electron's
            # internal minimized state. A normal Options+ launch restores it.
            Add-Type -Namespace InputSwitcher -Name NativeWindow `
                -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@
            $launchedProcess.Refresh()
            if ($launchedProcess.MainWindowHandle -ne 0) {
                [InputSwitcher.NativeWindow]::ShowWindowAsync(
                    $launchedProcess.MainWindowHandle,
                    0
                ) | Out-Null
            }
        }
        catch {
            # Window cosmetics must not turn a successful device switch into
            # a failure; the bridge remains usable if minimization is blocked.
        }
    }

    if ($result.source -eq "discovery" -and
        ($result.PSObject.Properties.Name -contains "cache") -and
        @($result.cache).Count -gt 0) {
        $newCache = @($result.cache | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                name = $_.name
                modelId = $_.modelId
            }
        })
        $newCacheJson = ConvertTo-Json -InputObject ([pscustomobject]@{
            devices = $newCache
        }) -Depth 5
        Write-Utf8IfChanged -Path $cachePath -Content $newCacheJson
    }

    if ($result.status -eq "NOT_CONNECTED") {
        Log "no connected keyboard found (mode=$($result.source), $($result.elapsedMs) ms)"
        $exitCode = 0
    }
    elseif ($result.success) {
        $switchText = @($result.switches | ForEach-Object {
            "$($_.name)=$($_.code)"
        }) -join ", "
        Log "switched host $TargetHost [$switchText] (mode=$($result.source), $($result.elapsedMs) ms)"
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
    if ($launchedByUs -and -not $bridgeReady -and $launchedProcess) {
        Stop-Process -Id $launchedProcess.Id -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $bridgeStatePath) {
            try {
                $failedState = Get-Content -LiteralPath $bridgeStatePath -Raw |
                    ConvertFrom-Json
                if ([int]$failedState.pid -eq $launchedProcess.Id) {
                    Remove-Item -LiteralPath $bridgeStatePath -Force
                }
            }
            catch {
                # A previous verified bridge state belongs to another process.
            }
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
