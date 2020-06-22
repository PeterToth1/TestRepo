@{
    "username" = $env:USER
    "password" = $env:PWD
} | ConvertTo-Json | Out-File 'settings.json'