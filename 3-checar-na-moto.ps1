# 3-checar-na-moto.ps1
# Verificacao com o adaptador JA PLUGADO na moto e ignicao LIGADA (motor desligado).
# SOMENTE LEITURA: nao escreve absolutamente nada na ECU.
# Confirma: tensao da bateria, protocolo CAN e se existe trafego real no barramento.

param(
  [string]$Port = "COM5",
  [int]$Baud = 38400
)

function Send-Cmd {
  param([System.IO.Ports.SerialPort]$sp, [string]$cmd, [int]$waitMs = 1500)
  $sp.DiscardInBuffer()
  $sp.Write("$cmd`r")
  $sb = New-Object System.Text.StringBuilder
  $fim = [DateTime]::UtcNow.AddMilliseconds($waitMs)
  while ([DateTime]::UtcNow -lt $fim) {
    if ($sp.BytesToRead -gt 0) {
      [void]$sb.Append($sp.ReadExisting())
      if ($sb.ToString().Contains('>')) { break }
    } else { Start-Sleep -Milliseconds 20 }
  }
  return ($sb.ToString() -replace "`r", "`n" -replace '>', '').Trim()
}

function Monitorar {
  # ATMA = monitor all. Escuta o barramento e devolve os quadros vistos.
  param([System.IO.Ports.SerialPort]$sp, [int]$segundos = 3)
  $sp.DiscardInBuffer()
  $sp.Write("ATMA`r")
  $sb = New-Object System.Text.StringBuilder
  $fim = [DateTime]::UtcNow.AddSeconds($segundos)
  while ([DateTime]::UtcNow -lt $fim) {
    if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
    else { Start-Sleep -Milliseconds 20 }
  }
  $sp.Write("`r")        # qualquer caractere interrompe o ATMA
  Start-Sleep -Milliseconds 400
  if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
  return ($sb.ToString() -replace "`r", "`n")
}

Write-Output "=== Verificacao na moto - porta $Port @ $Baud ==="
Write-Output ""

$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, 'None', 8, 'One')
$sp.ReadTimeout = 2000; $sp.WriteTimeout = 2000
$sp.DtrEnable = $true; $sp.RtsEnable = $true
try { $sp.Open() } catch { Write-Error "Nao consegui abrir $Port : $($_.Exception.Message)"; exit 1 }
Start-Sleep -Milliseconds 300

# A partir daqui a porta esta aberta. O trap garante que ela seja liberada
# mesmo se algo falhar no meio - senao a COM fica presa ate fechar o PowerShell
# e a proxima execucao acusa "acesso negado".
trap { if ($sp -and $sp.IsOpen) { $sp.Close() }; break }

$v = Send-Cmd $sp "ATZ" 3000
if ($v -notmatch 'ELM') { Write-Error "Adaptador nao respondeu (ATZ='$v')."; $sp.Close(); exit 1 }
Write-Output "[1] Adaptador ......... OK  ($(($v -split "`n")[-1].Trim()))"

[void](Send-Cmd $sp "ATE0" 800)
[void](Send-Cmd $sp "ATL0" 800)
[void](Send-Cmd $sp "ATS0" 800)
[void](Send-Cmd $sp "ATH1" 800)

# --- tensao: prova de que esta energizado pela moto ---
$rv = (Send-Cmd $sp "ATRV" 1500).Trim()
Write-Output "[2] Tensao da moto .... $rv"
$num = 0.0
[void][double]::TryParse(($rv -replace '[^0-9.]', ''), [ref]$num)
if ($num -lt 11.0) {
  Write-Output ""
  Write-Output "    !! Abaixo de 11 V. Provaveis causas:"
  Write-Output "       - ignicao desligada  - kill switch fora de RUN"
  Write-Output "       - conector nao encaixou  - bateria fraca"
  Write-Output "    Resolva isso antes de seguir."
}

# --- procura trafego CAN nos protocolos usados pela Triumph Keihin ---
Write-Output ""
Write-Output "[3] Procurando trafego no barramento CAN..."
$protos = @(
  @{ n = '6'; d = 'ISO 15765-4 CAN 11 bit / 500 kbps' },
  @{ n = '7'; d = 'ISO 15765-4 CAN 29 bit / 500 kbps' },
  @{ n = '8'; d = 'ISO 15765-4 CAN 11 bit / 250 kbps' },
  @{ n = '9'; d = 'ISO 15765-4 CAN 29 bit / 250 kbps' }
)
$achou = $null
foreach ($p in $protos) {
  [void](Send-Cmd $sp "ATSP$($p.n)" 1200)
  $saida = Monitorar $sp 3
  $linhas = $saida -split "`n" | Where-Object {
    $_ -match '^[0-9A-F]{3,8}\s' -and $_ -notmatch 'SEARCHING|UNABLE|NO DATA|ERROR|STOPPED|BUS INIT'
  }
  $qtd = ($linhas | Measure-Object).Count
  if ($qtd -gt 0) {
    Write-Output "    ATSP$($p.n)  $($p.d)"
    Write-Output "       -> $qtd quadros capturados. Exemplo:"
    $linhas | Select-Object -First 4 | ForEach-Object { Write-Output "          $($_.Trim())" }
    if (-not $achou) { $achou = $p }
  } else {
    Write-Output "    ATSP$($p.n)  $($p.d)  -> silencio"
  }
}

$sp.Close()

Write-Output ""
Write-Output "=============================================="
if ($achou) {
  Write-Output "RESULTADO: barramento ativo em ATSP$($achou.n) ($($achou.d))."
  Write-Output "A moto esta conversando. Pode abrir o TigerTool e selecionar a $Port."
} else {
  Write-Output "RESULTADO: nenhum trafego CAN detectado."
  Write-Output ""
  if ($num -ge 11.0) {
    # Tensao boa + silencio total = o conector esta certo, o problema e outro.
    Write-Output "  A tensao esta OK ($rv), entao o conector encaixou. Suspeitos, nesta ordem:"
    Write-Output ""
    Write-Output "  1. CHAVE HS CAN / MS CAN do adaptador na posicao errada."
    Write-Output "     Se o seu adaptador tem um interruptor lateral, passe para HS CAN."
    Write-Output "     Em MS CAN ele escuta os pinos 3/11, que na Triumph nao tem nada -"
    Write-Output "     tudo parece funcionar, mas nunca acha a moto."
    Write-Output "  2. Ignicao desligada ou kill switch fora de RUN (o barramento dorme)."
    Write-Output "  3. Adaptador clone ruim, apesar de responder aos comandos AT."
  } else {
    Write-Output "  A tensao esta baixa ($rv), entao comece por ai:"
    Write-Output "  ignicao ligada, kill switch em RUN e encaixe do conector."
  }
}
Write-Output "=============================================="
try { Read-Host "Enter para sair" } catch { }
