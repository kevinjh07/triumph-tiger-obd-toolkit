# 2-ajuste-ftdi.ps1
# Reduz o "latency timer" do driver FTDI de 16 ms para 2 ms.
# Motivo: 16 ms (padrao) causa timeout/queda de conexao em softwares ELM327.
# EXECUTAR COMO ADMINISTRADOR. Reversivel: basta rodar com -Reverter.

param([switch]$Reverter)

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
           [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Warning "Rode este script como Administrador (botao direito > Executar como administrador)."
  try { Read-Host "Enter para sair" } catch { }
  exit 1
}

$valor = if ($Reverter) { 16 } else { 2 }

$raizes = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\FTDIBUS' -ErrorAction SilentlyContinue
if (-not $raizes) { Write-Warning "Nenhum dispositivo FTDI encontrado no registro."; exit 1 }

foreach ($r in $raizes) {
  $dp = Join-Path $r.PSPath '0000\Device Parameters'
  if (-not (Test-Path $dp)) { continue }
  $p = Get-ItemProperty $dp
  Set-ItemProperty -Path $dp -Name LatencyTimer -Value $valor -Type DWord
  $novo = (Get-ItemProperty $dp).LatencyTimer
  Write-Output "$($p.PortName)  [$($r.PSChildName)]  LatencyTimer -> $novo ms"
}

Write-Output ""
Write-Output "Pronto. Desconecte e reconecte o cabo USB para aplicar."
try { Read-Host "Enter para sair" } catch { }
