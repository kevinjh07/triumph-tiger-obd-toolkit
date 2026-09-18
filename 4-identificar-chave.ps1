# 4-identificar-chave.ps1
# Descobre qual posicao do interruptor do adaptador e a HS CAN.
#
# Adaptadores ELM327 com chave HS CAN / MS CAN quase nunca vem com marcacao.
# Este script compara as duas posicoes: quem escutar trafego e a HS CAN.
#
# SOMENTE LEITURA: nao envia nenhum comando de escrita ao veiculo.
#
# Onde rodar: em QUALQUER carro 2008+ (o OBD-II obriga HS CAN nos pinos 6/14)
# ou na propria moto. Evite Ford e Mazda: eles usam MS CAN de verdade, entao
# as duas posicoes podem mostrar trafego e o teste fica ambiguo.

param(
  [string]$Port = "COM5",
  [int]$Baud = 38400,
  [int]$Segundos = 3
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

function Contar-Quadros {
  # Escuta o barramento em 500 kbps (11 e 29 bits) e conta quadros validos.
  param([System.IO.Ports.SerialPort]$sp)
  $total = 0
  $amostra = @()
  foreach ($proto in @('6', '7')) {
    [void](Send-Cmd $sp "ATSP$proto" 1200)
    $sp.DiscardInBuffer()
    $sp.Write("ATMA`r")
    $sb = New-Object System.Text.StringBuilder
    $fim = [DateTime]::UtcNow.AddSeconds($Segundos)
    while ([DateTime]::UtcNow -lt $fim) {
      if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
      else { Start-Sleep -Milliseconds 20 }
    }
    $sp.Write("`r")
    Start-Sleep -Milliseconds 400
    if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()) }
    $linhas = ($sb.ToString() -replace "`r", "`n") -split "`n" | Where-Object {
      $_ -match '^[0-9A-F]{3,8}\s' -and
      $_ -notmatch 'SEARCHING|UNABLE|NO DATA|ERROR|STOPPED|BUS INIT'
    }
    $total += ($linhas | Measure-Object).Count
    if ($amostra.Count -eq 0 -and $linhas.Count -gt 0) { $amostra = $linhas | Select-Object -First 2 }
  }
  return @{ Total = $total; Amostra = $amostra }
}

function Abrir-Porta {
  $sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, 'None', 8, 'One')
  $sp.ReadTimeout = 2000; $sp.WriteTimeout = 2000
  $sp.DtrEnable = $true; $sp.RtsEnable = $true
  $sp.Open()
  Start-Sleep -Milliseconds 300
  $v = Send-Cmd $sp "ATZ" 3000
  if ($v -notmatch 'ELM') { $sp.Close(); throw "Adaptador nao respondeu ao ATZ." }
  [void](Send-Cmd $sp "ATE0" 800)
  [void](Send-Cmd $sp "ATL0" 800)
  [void](Send-Cmd $sp "ATS0" 800)
  [void](Send-Cmd $sp "ATH1" 800)
  return $sp
}

function Medir {
  param([string]$rotulo)
  # As mensagens vao para o host, NAO para o fluxo de saida: esta funcao
  # devolve apenas o numero de quadros. Usar Write-Output aqui faria as
  # mensagens entrarem no valor de retorno, transformando o resultado num
  # array e quebrando as comparacoes la embaixo.
  $sp = Abrir-Porta
  try {
    $rv = (Send-Cmd $sp "ATRV" 1500).Trim()
    $num = 0.0
    [void][double]::TryParse(($rv -replace '[^0-9.]', ''), [ref]$num)
    Write-Host "  Tensao: $rv"
    if ($num -lt 11.0) {
      Write-Warning "  Tensao baixa. Ligue a ignicao e confirme o encaixe antes de continuar."
    }
    Write-Host "  Escutando o barramento..."
    $r = Contar-Quadros $sp
    Write-Host "  Posicao $rotulo -> $($r.Total) quadros"
    foreach ($l in $r.Amostra) { Write-Host "     $($l.Trim())" }
    return [int]$r.Total
  }
  finally {
    # Libera a porta entre as duas medicoes, mesmo se algo falhar.
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
  }
}

Write-Host ""
Write-Host "=============================================="
Write-Host " Identificacao da chave HS CAN / MS CAN"
Write-Host "=============================================="
Write-Host ""
Write-Host " Rode em um carro 2008+ (nao Ford/Mazda) ou na moto."
Write-Host " Ignicao LIGADA, motor desligado."
Write-Host ""
Write-Host " Marque fisicamente a posicao atual da chave antes de comecar"
Write-Host " (fita, caneta, foto) para nao se perder."
Write-Host ""
try { Read-Host " Enter para medir a POSICAO 1" | Out-Null } catch { }

Write-Host ""
Write-Host "--- POSICAO 1 ---"
try { $p1 = Medir "1" } catch { Write-Error $_; exit 1 }

Write-Host ""
Write-Host " Agora VIRE A CHAVE para a outra posicao."
try { Read-Host " Enter quando tiver virado" | Out-Null } catch { }

Write-Host ""
Write-Host "--- POSICAO 2 ---"
try { $p2 = Medir "2" } catch { Write-Error $_; exit 1 }

Write-Host ""
Write-Host "=============================================="
if ($p1 -gt 0 -and $p2 -eq 0) {
  Write-Host " A POSICAO 1 e a HS CAN. Deixe a chave nela."
} elseif ($p2 -gt 0 -and $p1 -eq 0) {
  Write-Host " A POSICAO 2 e a HS CAN. Deixe a chave nela."
} elseif ($p1 -gt 0 -and $p2 -gt 0) {
  Write-Host " As duas posicoes viram trafego."
  Write-Host " O veiculo provavelmente tem MS CAN de verdade (Ford/Mazda)."
  Write-Host " A HS CAN e a que capturou mais quadros: posicao $(if ($p1 -ge $p2) {'1'} else {'2'})."
  Write-Host " Para um resultado limpo, repita em outro veiculo."
} else {
  Write-Host " Nenhuma das posicoes viu trafego. O teste nao concluiu nada."
  Write-Host " Verifique ignicao ligada e encaixe do conector, e tente de novo."
}
Write-Host ""
Write-Host " Marque a posicao correta na carcaca para nao repetir isso."
Write-Host "=============================================="
try { Read-Host "Enter para sair" } catch { }
