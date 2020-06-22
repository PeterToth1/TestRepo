Set-ExecutionPolicy Bypass -Scope Process -Force

$curl = 'curl.exe'

function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String] $json) {
    $indent = 0;
    ($json -Split '\n' |
            % {
            if ($_ -match '[\}\]]') {
                # This line contains  ] or }, decrement the indentation level
                $indent--
            }
            $line = (' ' * $indent * 2) + $_.TrimStart().Replace(':  ', ': ')
            if ($_ -match '[\{\[]') {
                # This line contains [ or {, increment the indentation level
                $indent++
            }
            $line
        }) -Join "`n"
}

function CleanupAgents {
    param($agents)

    $processes = Get-Process -IncludeUserName
    foreach ($p in $processes) {
        # if ($p.UserName -match 'aumel-ccuser') {
            & taskkill.exe /f /im 'java.exe'
            & taskkill.exe /f /im 'wrapper-windows-x86-64.exe'
            & taskkill.exe /f /im 'cmd.exe'
        # }
    }

    foreach ($agent in $agents) {
        Stop-Service -Name $agent.Name -Force -ErrorAction SilentlyContinue
        
        $pos = $agent.PathName.IndexOf('-s')
        $filePath = Split-Path -Path $agent.PathName.Substring(0, $pos)
        $goDir = (get-item $filePath).parent.FullName
        Remove-Item -Path "$goDir\.agent-bootstrapper.running" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$goDir\config" -Force -Recurse -ErrorAction SilentlyContinue
    }

    # Disable and delete Go agents from the server
    DeleteAgentsFromServer
}

function StartAgents {
    param($agents)

    # start main go process
    $pos = $agents[0].PathName.IndexOf('-s')
    $filePath = Split-Path -Path $agents[0].PathName.Substring(0, $pos)
    $goDir = (get-item $filePath).parent.FullName
    Start-Process "$goDir\bin\go-agent.bat"

    # start go services
    for ($i = 1; $i -lt $agents.Count; $i++) {
        Start-Service -Name $agents[$i].Name
    }
}

function DeleteFile ($filename) {
    if (Test-Path -Path $filename) {
        Remove-Item $filename -Force -ErrorAction SilentlyContinue
    }
}

function DeleteAgentsFromServer {
    $payload = 'payload.json'
    DeleteFile $payload

    # get credentials, url from settings
    # $settings = (Get-Content 'settings.json').TrimStart('"').TrimEnd('"').Replace("\", "") | ConvertFrom-Json
    
    $user = 'aumel-ccuser' + ':' + ${env:AUMEL-CCUSER}
    $url = $settings.go_url + '/api/agents'
    
    & $curl --insecure $url -u $user -H 'Accept: application/vnd.go.cd.v5+json' -o $payload
    $agentInfo = Get-Content $payload | Out-String | ConvertFrom-Json
    DeleteFile $payload

    if ($null -ne $agentInfo) {
        $agents = $agentInfo._embedded.agents | Where-Object {$_.hostname.ToUpper() -eq $env:computername.ToUpper()}
        
        if ($agents.Count -eq 0) { return }

        if ($agents.Count -eq 1) {
            @{ agent_config_state = 'disabled' } | ConvertTo-Json | Format-Json | Out-File $payload -Encoding ascii

            $uuid = $agents[0].uuid
            & $curl --trace-ascii - --insecure "$url/$uuid" -u $user -H 'Accept: application/vnd.go.cd.v5+json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -X PATCH --data-binary '@payload.json'
            Start-Sleep -Seconds 2
            & $curl --trace-ascii - --insecure "$url/$uuid" -u $user -H 'Accept: application/vnd.go.cd.v5+json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -X DELETE --data-binary '@payload.json'
        }
        else {            
            $uuids = $agents | ForEach-Object {$_.uuid}
            @{
                uuids = $uuids
                agent_config_state = 'disabled'
            } | ConvertTo-Json | Format-Json | Out-File $payload -Encoding ascii

            & $curl --trace-ascii - --insecure $url -u $user -H 'Accept: application/vnd.go.cd.v5+json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -X PATCH --data-binary '@payload.json'
            Start-Sleep -Seconds 2
            & $curl --trace-ascii - --insecure $url -u $user -H 'Accept: application/vnd.go.cd.v5+json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -X DELETE --data-binary '@payload.json'
        }

        DeleteFile $payload
    }
}

# get the go agents installed the PC
$agents = Get-CimInstance -ClassName win32_service | Where-Object {$_.Name -match 'Go Agent'} | Select-Object Name, DisplayName, State, PathName

CleanupAgents -agents $agents
StartAgents -agents $agents