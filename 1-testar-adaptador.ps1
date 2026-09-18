# 1-testar-adaptador.ps1
# Teste de bancada do adaptador ELM327, com o cabo ligado SO no USB.
# Varre as velocidades comuns e conversa com o chip para confirmar que ele
# responde. Nao precisa da moto e nao se conecta a veiculo nenhum.

param(
  [string]$Port = "COM5",
  [int[]]$Bauds = @(38400, 9600, 115200, 500000)
)

function Invoke-Elm {
  param([System.IO.Ports.SerialPort]$sp, [string]$cmd, [int]$waitMs = 1200)
  $sp.DiscardInBuffer()
  $sp.Write("$cmd`r")
  $sb = New-Object System.Text.StringBuilder
  $deadline = [DateTime]::UtcNow.AddMilliseconds($waitMs)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($sp.BytesToRead -gt 0) {
      [void]$sb.Append($sp.ReadExisting())
      if ($sb.ToString().Contains('>')) { break }
    } else { Start-Sleep -Milliseconds 30 }
  }
  return ($sb.ToString() -replace "`r", "`n" -replace '>', '').Trim()
}

foreach ($baud in $Bauds) {
  Write-Output "=== Tentando $Port @ $baud ==="
  $sp = New-Object System.IO.Ports.SerialPort($Port, $baud, 'None', 8, 'One')
  $sp.ReadTimeout = 2000; $sp.WriteTimeout = 2000
  $sp.DtrEnable = $true; $sp.RtsEnable = $true
  try { $sp.Open() } catch { Write-Output "  ! Falha ao abrir: $($_.Exception.Message)"; continue }
  Start-Sleep -Milliseconds 300

  # O finally garante que a porta seja liberada mesmo se algo lancar excecao.
  # Sem isso a COM fica presa e a proxima execucao falha com "acesso negado".
  try {
    $id = Invoke-Elm $sp "ATZ" 3000
    if ($id -notmatch 'ELM|OBD|v\d') {
      Write-Output "  sem resposta valida ('$id')"
      continue
    }

    Write-Output "  >>> CONECTADO em $baud <<<"
    Write-Output "  ATZ  (reset/versao) : $id"
    [void](Invoke-Elm $sp "ATE0" 800)   # eco off
    foreach ($c in @('ATI','AT@1','AT@2','ATDPN','ATDP','ATRV','ATIGN','STI')) {
      $r = Invoke-Elm $sp $c 1200
      Write-Output ("  {0,-6}: {1}" -f $c, ($r -replace "`n", ' | '))
    }
    Write-Output ""
    Write-Output "RESULTADO: adaptador funcional na porta $Port, baud $baud"
    exit 0
  }
  finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
  }
}
Write-Output "Nenhum baud respondeu. Verifique cabo/porta."
exit 1
