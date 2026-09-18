# Triumph Tiger — OBD Toolkit

Resetar o indicador de revisão (a *chave inglesa* do painel) de uma Triumph Tiger
usando um adaptador **ELM327 USB** barato e um PC com **Windows** — sem ir à
concessionária e sem comprar ferramenta proprietária.

Este repositório reúne **scripts de verificação em PowerShell** e um **guia
passo a passo** com as armadilhas que fazem a maioria das pessoas desistir no
meio do caminho.

> Validado em uma **Triumph Tiger 800 XRx 2016**, com ELM327 v1.5
> (PIC18F25K80 + FTDI FT232R) no Windows 11.

---

## Índice

- [Resumo rápido](#resumo-rápido)
- [O problema](#o-problema)
- [1. Hardware](#1-hardware)
- [2. Software: use TigerTool, não TuneECU](#2-software-use-tigertool-não-tuneecu)
- [3. Preparando o PC](#3-preparando-o-pc)
- [4. Os scripts deste repositório](#4-os-scripts-deste-repositório)
- [5. Procedimento na moto](#5-procedimento-na-moto)
- [6. Intervalos de revisão](#6-intervalos-de-revisão)
- [7. Solução de problemas](#7-solução-de-problemas)
- [Compatibilidade](#compatibilidade)
- [Avisos importantes](#avisos-importantes)
- [Licença](#licença)

---

## Resumo rápido

Se você só quer a resposta, é esta:

| | |
|---|---|
| **Adaptador** | ELM327 v1.5 USB (chip FTDI ou CH340). ~R$ 50–120. |
| **Conector na moto** | OBD-II preto de **16 pinos**, sob o banco do carona. **Sem adaptador.** |
| **Software** | **TigerTool** (gratuito, Windows) |
| **Software que NÃO serve** | TuneECU — não suporta USB nesta geração, e não tem mais versão Windows |
| **Onde reseta** | Aba `Insts` do TigerTool |
| **Condição da moto** | Ignição ligada, motor desligado, kill switch em `RUN` |

---

## O problema

A chave inglesa acende no painel e o manual manda ir à concessionária. Ao
pesquisar, você encontra três informações — e **duas delas provavelmente vão
te fazer perder tempo ou dinheiro**:

1. *"Use TuneECU"* — o conselho mais repetido nos fóruns. Só que, dependendo do
   ano da sua moto, o TuneECU **não funciona com adaptador USB**, e a versão
   Windows dele foi descontinuada há mais de uma década.
2. *"Você precisa de um adaptador de 6 pinos"* — verdade apenas para modelos
   **2024+**. Em motos anteriores o ELM327 comum encaixa direto.
3. *"Só a concessionária consegue"* — falso. O reset é feito por software.

Este guia existe para você não cair em nenhuma das três.

---

## 1. Hardware

### 1.1 O adaptador ELM327

O **ELM327** é um chip que traduz o barramento do veículo (CAN, K-line) para
comandos de texto simples numa porta serial. Praticamente todo adaptador OBD-II
barato é uma cópia dele.

Nem todo clone presta. O que procurar:

| Característica | Por quê |
|---|---|
| **Versão 1.5** | Versões "2.1" de clone quase sempre são falsas e com firmware pior. A 1.5 é a mais compatível com software de moto. |
| **Chip USB FTDI ou CH340** | Define o driver. FTDI costuma ser mais estável. |
| **Microcontrolador PIC18F25K80** | Indica um clone de boa qualidade, com firmware mais completo. |
| **Conexão USB** | Para TigerTool no PC. Bluetooth serve para o app TuneECU no Android. |

### 1.2 Como saber se o seu adaptador presta

Plugue o adaptador **só no USB** (sem a moto) e rode:

```powershell
.\1-testar-adaptador.ps1
```

O script varre as velocidades comuns (38400, 9600, 115200, 500000) e conversa
com o chip. Saída de um adaptador saudável:

```
=== Tentando COM5 @ 38400 ===
  >>> CONECTADO em 38400 <<<
  ATI   : ELM327 v1.5
  AT@1  : OBDII to RS232 Interpreter
  ATDP  : AUTO, ISO 15765-4 (CAN 29/500)
  ATRV  : 0.0V
```

`ATRV` marcar **0.0V é normal aqui** — o adaptador mede a tensão da moto, e
ela ainda não está conectada.

<details>
<summary>O que cada comando significa</summary>

| Comando | Função |
|---|---|
| `ATZ` | Reset do adaptador; devolve a versão do firmware |
| `ATI` | Identificação da versão |
| `AT@1` | Descrição do fabricante |
| `ATE0` | Desliga o eco (não repetir o que foi enviado) |
| `ATDP` / `ATDPN` | Protocolo em uso (nome / número) |
| `ATRV` | Tensão lida no pino de alimentação |
| `ATSP<n>` | Força um protocolo específico |
| `ATMA` | *Monitor All* — escuta o barramento sem transmitir nada |

</details>

### 1.3 O conector da moto

Na Tiger 800 (e na maioria das Triumph até ~2023) o conector de diagnóstico é o
**OBD-II preto de 16 pinos**, igual ao de carro, sob o **banco do carona, lado
direito**, protegido por uma capa emborrachada.

| Geração | Conector | Precisa adaptador? |
|---|---|---|
| Até ~2023 | OBD-II 16 pinos, preto | **Não** — liga direto |
| 2024+ | 6 pinos vermelho (Euro 5, ISO 19689) | **Sim** — cabo 16→6 pinos |

> Muita gente compra o adaptador de 6 pinos sem precisar, porque os fóruns
> misturam as gerações. Confira o seu conector antes de comprar.

---

## 2. Software: use TigerTool, não TuneECU

### 2.1 Por que TuneECU não resolve

O TuneECU é excelente e é a referência para Triumph — **mas só nas combinações
que ele suporta**. A lista oficial de compatibilidade traz colunas separadas
para cada tipo de interface. Compare duas linhas:

```
Bikes                                      USB(1)   OBD(2)  OBDLink(3)
Tiger 800, 800 XC (até 2014)               D/R/W      D         D
Tiger 800 XC, XCX, XR, XRX (2015-2017)    (vazio)     D        D/W
```

`D` = diagnóstico · `R` = ler mapa · `W` = gravar mapa

Na geração 2015–2017 a **coluna USB está vazia**. Só há suporte via Bluetooth
(`OBD`) ou OBDLink. Somando a isso:

- A **versão Windows do TuneECU foi descontinuada** — a última foi a 2.5.8, de
  cerca de 2012, e não cobre as motos com CAN mais novas.
- Os modelos recentes são atendidos apenas pelo **aplicativo Android**.

Ou seja: com ELM327 **USB** + **Windows**, o TuneECU está fora. Para usá-lo você
precisaria de um adaptador **Bluetooth** (ELM327 BT ou, garantido, um OBDLink
LX/MX+) e de um celular Android.

### 2.2 TigerTool

O **TigerTool** é um utilitário gratuito para uso não comercial, escrito pelo
autor conhecido como **T800XC** (*Little Dog Systems*). Ele:

- roda em **Windows** (binário nativo de 32 bits, não precisa .NET);
- fala com **ELM327 comum por porta COM**, versões `V1.n` ou `V2.n`;
- cobre Tiger 800, 900, Sport, Explorer/1200, Trophy, Speed Triple, Trident 660;
- **reseta o intervalo de revisão na aba `Insts`**, além de ler e apagar códigos
  de falha, balancear corpos de borboleta e sangrar o ABS.

### 2.3 Onde baixar

A distribuição oficial é por anexo no fórum **tiger800.co.uk**, que exige
cadastro. Atenção: esse fórum usa **bloqueio do Cloudflare por região** — em
alguns países ele retorna *"Sorry, you have been blocked"* e **VPN muitas vezes
não resolve**.

Rota alternativa confiável: o servidor da **BMDiag**, empresa que vende a
interface OBD oficial do TigerTool e hospeda o manual dele. A listagem de
diretório é negada, mas os arquivos são servidos direto pelo nome exato:

```
https://www.bmdiag.co.uk/user/tiger%20tool/TigerToolV3.7.zip   (v3.7, 2025)
https://www.bmdiag.co.uk/user/tiger%20tool/TigerTool.zip       (v3.5.1, 2024)
```

O manual em PDF está em:

```
https://www.bmdiag.co.uk/user/tiger%20tool/TigerTool%20V3.0%20Instructions.pdf
https://coeleveld.com/wp-content/uploads/2019/02/TigerTool-V3.7-Instructions.pdf
```

### 2.4 Verificando o que você baixou

O TigerTool **não é assinado digitalmente** — normal para utilitário gratuito de
hobbyista, mas significa que o SmartScreen vai avisar na primeira execução
(*Mais informações* → *Executar assim mesmo*). Confira os metadados antes:

```powershell
$exe = ".\TigerTool.exe"
(Get-Item $exe).VersionInfo | Format-List ProductName, FileVersion, CompanyName, LegalCopyright
Get-FileHash $exe -Algorithm SHA256
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -Scan -ScanType 3 -File (Resolve-Path $exe)
```

Valores esperados para a **v3.7**:

| Campo | Valor |
|---|---|
| ProductName | `TigerTool` |
| FileVersion | `3.7.0.0` |
| CompanyName | `Little Dog Systems` |
| LegalCopyright | `(C) 2025 - T800XC` |
| SHA-256 (.exe) | `429A489317A0F06BAF892BEC704496CD98424171731583C153DA26C2CCB9A470` |
| SHA-256 (.zip) | `A5926E0D815DD7C221F795AE994DBDFDF51C1F92FE98475E82CA4A1FB658CF2D` |

> Os binários **não são redistribuídos aqui** — são software de terceiros, com
> direitos do autor original. Baixe da fonte e confira o hash.

---

## 3. Preparando o PC

### 3.1 Driver

- **FTDI** (`VID_0403`): o Windows costuma instalar sozinho. Se não, use o
  driver VCP do site da FTDI.
- **CH340 / CP210x**: instale o driver correspondente ao chip.

### 3.2 Descobrir a porta COM

```powershell
Get-PnpDevice -Class Ports | Select-Object Status, FriendlyName, InstanceId
```

Procure algo como `USB Serial Port (COM5)`. Anote o número — todos os scripts
aceitam `-Port COMx` (o padrão é `COM5`).

### 3.3 Ajuste de latência (FTDI) — não pule

O driver FTDI vem com **latency timer de 16 ms**. Esse valor faz o driver
esperar até 16 ms antes de entregar bytes recebidos, o que **derruba a conexão**
de softwares ELM327, que esperam resposta rápida. Baixar para **2 ms** resolve
travamentos e erros de "no response" intermitentes.

```powershell
# clique direito > Executar como administrador
.\2-ajuste-ftdi.ps1

# para desfazer
.\2-ajuste-ftdi.ps1 -Reverter
```

Depois **desconecte e reconecte o cabo USB** para aplicar.

> Só se aplica a adaptadores FTDI. Com CH340/CP210x, pule.

---

## 4. Os scripts deste repositório

| Script | Quando usar | Escreve na ECU? |
|---|---|---|
| `1-testar-adaptador.ps1` | Na bancada, antes de tudo | Não — nem conecta na moto |
| `2-ajuste-ftdi.ps1` | Uma vez, como administrador | Não — mexe no registro do Windows |
| `3-checar-na-moto.ps1` | Com a moto ligada, antes de abrir o TigerTool | **Não — somente leitura** |

Todos aceitam `-Port` e, quando faz sentido, `-Baud`:

```powershell
.\1-testar-adaptador.ps1 -Port COM7
.\3-checar-na-moto.ps1   -Port COM7 -Baud 38400
```

### O que o `3-checar-na-moto.ps1` faz

É o script que economiza tempo. Antes de você culpar o software, ele confirma
a camada física:

1. **Tensão** (`ATRV`) — deve ler ~12 V. É a prova de que o conector encaixou e
   a ignição está ligada.
2. **Varredura de protocolo** — testa `ATSP6` a `ATSP9` (CAN 11/29 bits,
   500/250 kbps).
3. **Tráfego real** (`ATMA`) — escuta o barramento e mostra os quadros
   capturados. Se aparecerem quadros, a moto está conversando.

Nenhum byte de escrita é enviado à ECU.

Exemplo de saída com tudo certo:

```
[1] Adaptador ......... OK  (ELM327 v1.5)
[2] Tensao da moto .... 12.4V
[3] Procurando trafego no barramento CAN...
    ATSP6  ISO 15765-4 CAN 11 bit / 500 kbps
       -> 47 quadros capturados. Exemplo:
          18F00300 12 7D 00 00 00 00 00 00
```

---

## 5. Procedimento na moto

1. Remova o **banco do carona**. Localize o conector preto de 16 pinos à direita.
2. Conecte o ELM327 na moto e o USB no notebook.
3. **Kill switch em `RUN`.**
4. **Ignição ligada, motor desligado.**
5. Rode `.\3-checar-na-moto.ps1` e confirme tensão ~12 V e tráfego CAN.
6. Abra o **TigerTool** → botão **`Select Port`** → escolha sua **COM**.
7. Vá na aba **`Insts`** → ajuste o intervalo / limpe a chave inglesa.
8. Desligue a ignição, desconecte o cabo, recoloque o banco.

> **Bateria:** ignição ligada com motor parado consome. Se for demorar, use um
> carregador de manutenção — ECU perdendo alimentação no meio de uma escrita é
> o cenário que você quer evitar.

---

## 6. Intervalos de revisão

Referência para a Tiger 800, útil na hora de definir o próximo valor:

| Serviço | Intervalo |
|---|---|
| Primeira revisão | 800 km / 500 mi |
| Revisão normal | **10.000 km / 6.000 mi** ou 12 meses |
| Revisão maior (válvulas, velas, filtro de ar) | 20.000 km / 12.000 mi |
| Fluido de freio | 2 anos |
| Líquido de arrefecimento | 3 anos |

Confirme no manual do seu ano/mercado — pode variar.

---

## 7. Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `ATRV` mostra 0.0 V na moto | Ignição desligada, kill switch fora de `RUN`, ou conector mal encaixado | Revise os três antes de qualquer outra coisa |
| Script não acha a porta | Driver ausente ou porta errada | `Get-PnpDevice -Class Ports`; instale o driver do chip |
| Conecta e cai no meio | Latency timer do FTDI em 16 ms | Rode `2-ajuste-ftdi.ps1` como admin e reconecte o USB |
| Nenhum tráfego CAN, mas 12 V OK | Barramento dorme sem ignição | Confirme ignição ligada; teste com o painel aceso |
| Adaptador não responde a `ATZ` | Clone ruim ou baud diferente | O script varre 4 velocidades; se nenhuma responder, troque o adaptador |
| SmartScreen bloqueia o TigerTool | Executável não assinado | *Mais informações* → *Executar assim mesmo*, após conferir o hash |
| Site tiger800.co.uk bloqueado | Bloqueio do Cloudflare por região | Use o espelho da BMDiag (seção 2.3) |

---

## Compatibilidade

**Testado:** Triumph Tiger 800 XRx 2016 · ELM327 v1.5 FTDI · Windows 11.

**Deve funcionar** (segundo a documentação do TigerTool): Tiger 800, Tiger 900,
Tiger Sport, Tiger Explorer / 1200, Trophy, Speed Triple, Trident 660.

Os scripts em si são genéricos: servem para **qualquer moto ou carro com
ELM327** como diagnóstico de camada física, já que só leem. O que é específico
da Triumph é o TigerTool.

Rodou em outro modelo? Abra uma *issue* contando o resultado.

---

## Avisos importantes

- **Os scripts deste repositório são somente leitura.** Não enviam nenhum
  comando de escrita para a ECU.
- **Não tente forçar o reset com comandos crus.** Mandar escrita "às cegas" em
  módulo de moto pode corromper configuração. O TigerTool existe porque alguém
  já fez o trabalho de mapear isso corretamente.
- **O TigerTool é software de terceiros**, não assinado e fornecido *as-is*.
  Confira a origem e o hash antes de executar.
- **Resetar o indicador não faz a revisão.** O contador é um lembrete; troque o
  óleo de verdade.
- Mexer na ECU pode ter implicações de garantia. Decisão sua.

---

## Licença

Os scripts e a documentação deste repositório estão sob a licença
[MIT](LICENSE).

**Não se aplica ao TigerTool**, que é software de terceiros com direitos do
autor original (T800XC / Little Dog Systems), distribuído gratuitamente para uso
não comercial. Este repositório não redistribui o binário — apenas documenta
onde obtê-lo e como verificá-lo.
