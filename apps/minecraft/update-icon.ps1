# Gera o ConfigMap a partir do PNG local, sem acessar o cluster.
$ErrorActionPreference = 'Stop'
$iconPath = Join-Path $PSScriptRoot 'assets/server-icon.png'
$manifestPath = Join-Path $PSScriptRoot 'server-icon.yaml'
$iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
$pngSignature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
if ($iconBytes.Length -lt 24) {
    throw 'O arquivo precisa ser um PNG válido de 64x64 pixels.'
}
for ($index = 0; $index -lt $pngSignature.Length; $index++) {
    if ($iconBytes[$index] -ne $pngSignature[$index]) {
        throw 'O arquivo precisa estar no formato PNG.'
    }
}
$width = $iconBytes[16] * 16777216 + $iconBytes[17] * 65536 + $iconBytes[18] * 256 + $iconBytes[19]
$height = $iconBytes[20] * 16777216 + $iconBytes[21] * 65536 + $iconBytes[22] * 256 + $iconBytes[23]
if ($width -ne 64 -or $height -ne 64) {
    throw "O Minecraft exige 64x64 pixels; recebido: ${width}x${height}."
}
$encodedIcon = [Convert]::ToBase64String($iconBytes)
@"
apiVersion: v1
kind: ConfigMap
metadata:
  name: minecraft-server-icon
  namespace: laboratorio
binaryData:
  server-icon.png: $encodedIcon
"@ | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output 'server-icon.yaml atualizado. Aplique a pasta apps/minecraft/ na VPS.'
