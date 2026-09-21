# Renders a VoltRescue Markdown document to a print-quality PDF.
#
# There is no pandoc, wkhtmltopdf or Node on this machine, so the pipeline is
# Markdown -> HTML -> headless Edge -> PDF. Mermaid diagrams are drawn as real
# vector graphics by Mermaid.js rather than being dropped or left as code.
#
#   powershell -ExecutionPolicy Bypass -File tools\md-to-pdf.ps1 -Source 01_VoltRescue_Process_Flow_Guide.md
#
# -KeepHtml leaves the intermediate file behind, which is the quickest way to
# diagnose a diagram that will not draw.

param(
  [Parameter(Mandatory = $true)][string]$Source,
  [string]$Output,
  [string]$Subtitle = 'Business process and operations',
  [switch]$KeepHtml
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if (-not [System.IO.Path]::IsPathRooted($Source)) { $Source = Join-Path $root $Source }
if (-not (Test-Path $Source)) { throw "Source document not found: $Source" }
if (-not $Output) { $Output = [System.IO.Path]::ChangeExtension($Source, 'pdf') }

$edge = @(
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Neither Edge nor Chrome was found; one of them is required to produce the PDF." }

# ---------------------------------------------------------------------------
# Inline formatting. Order matters: escape first so that document text cannot
# inject markup, then re-introduce the small set of tags we generate ourselves.
# ---------------------------------------------------------------------------
function Convert-Inline([string]$text) {
  if ($null -eq $text) { return '' }
  $t = $text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'

  # Code spans are protected from every other rule by parking them first.
  $spans = New-Object System.Collections.ArrayList
  $t = [regex]::Replace($t, '`([^`]+)`', {
      param($m)
      $i = $spans.Add('<code>' + $m.Groups[1].Value + '</code>')
      return [char]0x1 + "$i" + [char]0x2
    })

  $t = [regex]::Replace($t, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
  $t = [regex]::Replace($t, '\*\*\*(.+?)\*\*\*', '<strong><em>$1</em></strong>')
  $t = [regex]::Replace($t, '\*\*(.+?)\*\*', '<strong>$1</strong>')
  $t = [regex]::Replace($t, '(?<![\w*])\*([^*]+)\*(?![\w*])', '<em>$1</em>')
  $t = [regex]::Replace($t, '~~(.+?)~~', '<del>$1</del>')

  $t = [regex]::Replace($t, [char]0x1 + '(\d+)' + [char]0x2, { param($m) $spans[[int]$m.Groups[1].Value] })
  return $t
}

function Split-Row([string]$line) {
  $s = $line.Trim()
  if ($s.StartsWith('|')) { $s = $s.Substring(1) }
  if ($s.EndsWith('|')) { $s = $s.Substring(0, $s.Length - 1) }
  return @($s -split '(?<!\\)\|') | ForEach-Object { $_.Trim() -replace '\\\|', '|' }
}

# ---------------------------------------------------------------------------
# Block-level conversion.
# ---------------------------------------------------------------------------
$lines = [System.IO.File]::ReadAllLines($Source)
$html = New-Object System.Text.StringBuilder
$i = 0
$diagrams = 0

function Add-Html([string]$s) { [void]$html.AppendLine($s) }

while ($i -lt $lines.Count) {
  $line = $lines[$i]
  $trim = $line.Trim()

  # --- fenced blocks -------------------------------------------------------
  if ($trim -match '^```(.*)$') {
    $lang = $Matches[1].Trim()
    $i++
    $buf = New-Object System.Collections.ArrayList
    while ($i -lt $lines.Count -and $lines[$i].Trim() -notmatch '^```') { [void]$buf.Add($lines[$i]); $i++ }
    $i++
    $body = ($buf -join "`n")
    if ($lang -eq 'mermaid') {
      # Escaped, not raw: a <br/> inside a node label would otherwise be parsed
      # as a real element by the browser and vanish from textContent, which is
      # where Mermaid reads the diagram from - so the line break was lost.
      $diagrams++
      $src = $body -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
      Add-Html "<figure class=""diagram""><pre class=""mermaid"">$src</pre></figure>"
    }
    else {
      $esc = $body -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
      Add-Html "<pre class=""code""><code>$esc</code></pre>"
    }
    continue
  }

  # --- tables --------------------------------------------------------------
  if ($trim.StartsWith('|') -and ($i + 1) -lt $lines.Count -and $lines[$i + 1].Trim() -match '^\|[\s:|-]+\|?$') {
    $head = Split-Row $line
    $i += 2
    Add-Html '<table><thead><tr>'
    foreach ($c in $head) { Add-Html ("<th>" + (Convert-Inline $c) + "</th>") }
    Add-Html '</tr></thead><tbody>'
    while ($i -lt $lines.Count -and $lines[$i].Trim().StartsWith('|')) {
      $cells = Split-Row $lines[$i]
      Add-Html '<tr>'
      foreach ($c in $cells) { Add-Html ("<td>" + (Convert-Inline $c) + "</td>") }
      Add-Html '</tr>'
      $i++
    }
    Add-Html '</tbody></table>'
    continue
  }

  # --- headings ------------------------------------------------------------
  if ($trim -match '^(#{1,6})\s+(.*)$') {
    $level = $Matches[1].Length
    $text = Convert-Inline $Matches[2]
    # Each numbered top-level section starts a fresh page.
    $cls = if ($level -eq 2 -and $Matches[2] -match '^\d+\.') { ' class="section-start"' } else { '' }
    Add-Html "<h$level$cls>$text</h$level>"
    $i++
    continue
  }

  # --- horizontal rule -----------------------------------------------------
  if ($trim -match '^(-{3,}|\*{3,}|_{3,})$') { Add-Html '<hr>'; $i++; continue }

  # --- blockquote ----------------------------------------------------------
  if ($trim.StartsWith('>')) {
    $buf = New-Object System.Collections.ArrayList
    while ($i -lt $lines.Count -and $lines[$i].Trim().StartsWith('>')) {
      [void]$buf.Add(($lines[$i].Trim() -replace '^>\s?', ''))
      $i++
    }
    Add-Html ('<blockquote>' + (Convert-Inline ($buf -join ' ')) + '</blockquote>')
    continue
  }

  # --- lists ---------------------------------------------------------------
  if ($trim -match '^([-*+]|\d+\.)\s+') {
    $ordered = $trim -match '^\d+\.'
    $tag = if ($ordered) { 'ol' } else { 'ul' }
    Add-Html "<$tag>"
    while ($i -lt $lines.Count) {
      $l = $lines[$i]
      $lt = $l.Trim()
      if ($lt -match '^([-*+]|\d+\.)\s+(.*)$') {
        $item = $Matches[2]
        $i++
        # Fold any wrapped continuation lines into the same bullet.
        while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '' -and
               $lines[$i].Trim() -notmatch '^([-*+]|\d+\.)\s+' -and
               $lines[$i].Trim() -notmatch '^(#{1,6}\s|```|\||>)') {
          $item += ' ' + $lines[$i].Trim()
          $i++
        }
        Add-Html ('<li>' + (Convert-Inline $item) + '</li>')
      }
      elseif ($lt -eq '') {
        if (($i + 1) -lt $lines.Count -and $lines[$i + 1].Trim() -match '^([-*+]|\d+\.)\s+') { $i++ } else { break }
      }
      else { break }
    }
    Add-Html "</$tag>"
    continue
  }

  # --- blank ---------------------------------------------------------------
  if ($trim -eq '') { $i++; continue }

  # --- paragraph -----------------------------------------------------------
  $buf = New-Object System.Collections.ArrayList
  while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '' -and
         $lines[$i].Trim() -notmatch '^(#{1,6}\s|```|\||>|[-*+]\s|\d+\.\s|-{3,}$)') {
    [void]$buf.Add($lines[$i].Trim())
    $i++
  }
  if ($buf.Count) { Add-Html ('<p>' + (Convert-Inline ($buf -join ' ')) + '</p>') }
  else { $i++ }
}

# ---------------------------------------------------------------------------
# Page shell.
# ---------------------------------------------------------------------------
$docTitle = [System.IO.Path]::GetFileNameWithoutExtension($Source) -replace '^\d+_', '' -replace '_', ' '
$generated = Get-Date -Format 'dddd d MMMM yyyy'

$template = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>__TITLE__</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
<style>
  /* preferCSSPageSize is on, so page geometry is defined here. */
  @page { size: A4 portrait; margin: 14mm 16mm 16mm 16mm; }
  * { box-sizing: border-box; }
  body {
    font-family: "Segoe UI", Calibri, system-ui, sans-serif;
    font-size: 10.5pt; line-height: 1.45; color: #1b2330; margin: 0;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
  }
  h1, h2, h3, h4 { color: #0f2545; line-height: 1.25; margin: 0 0 .45em; font-weight: 600; }
  h1 { font-size: 22pt; }
  h2 { font-size: 15pt; margin-top: 1.5em; padding-bottom: .25em; border-bottom: 2px solid #1d7a5f; }
  h3 { font-size: 12pt; margin-top: 1.3em; color: #16324f; }
  h4 { font-size: 10.8pt; margin-top: 1.1em; color: #37506b; }
  h2.section-start { page-break-before: always; }
  h3, h4 { page-break-after: avoid; }
  p { margin: 0 0 .6em; text-align: justify; }
  a { color: #14634f; text-decoration: none; }
  strong { color: #0f2545; }
  hr { border: 0; border-top: 1px solid #dfe5ec; margin: 1.4em 0; }
  code { font-family: Consolas, "Courier New", monospace; font-size: .88em;
         background: #eef2f7; padding: 1px 4px; border-radius: 3px; color: #123; }
  pre.code { background: #f5f8fb; border: 1px solid #dde4ec; border-left: 3px solid #1d7a5f;
             border-radius: 4px; padding: 9px 12px; overflow: hidden; page-break-inside: avoid; }
  pre.code code { background: none; padding: 0; font-size: .82em; white-space: pre-wrap; }
  blockquote { margin: 0 0 .9em; padding: .55em .9em; background: #f2f7f5;
               border-left: 3px solid #1d7a5f; color: #24424f; page-break-inside: avoid; }
  blockquote p { margin: 0; }
  ul, ol { margin: 0 0 .8em; padding-left: 1.4em; }
  li { margin-bottom: .25em; }

  /* Long tables split across pages rather than jumping whole to the next one,
     which used to strand half-empty pages behind them. Individual rows stay
     intact and the header repeats on each continuation. */
  table { width: 100%; border-collapse: collapse; margin: .4em 0 .9em;
          font-size: 9.2pt; page-break-inside: auto; }
  tr { page-break-inside: avoid; page-break-after: auto; }
  thead { display: table-header-group; }
  th { background: #0f2545; color: #fff; text-align: left; font-weight: 600;
       padding: 6px 8px; border: 1px solid #0f2545; }
  td { padding: 4px 8px; border: 1px solid #d7dee7; vertical-align: top; }
  tbody tr:nth-child(even) { background: #f6f9fc; }

  figure.diagram { margin: 1em 0 1.3em; padding: 6px; text-align: center;
                   background: #fbfcfe; border: 1px solid #e2e8f0; border-radius: 6px;
                   page-break-inside: avoid; }
  figure.diagram svg { max-width: 100%; height: auto; }

  /* Cover */
  .cover { page-break-after: always; padding-top: 42mm; text-align: center; }
  .cover .mark { width: 54px; height: 54px; border-radius: 14px; margin: 0 auto 18px;
                 background: linear-gradient(135deg, #2bd4a8, #2f7cf6); }
  .cover h1 { font-size: 28pt; margin-bottom: 6px; }
  .cover .sub { font-size: 13pt; color: #3d566e; margin-bottom: 26px; }
  .cover .rule { width: 66px; height: 3px; background: #1d7a5f; margin: 0 auto 26px; }
  .cover table { width: 78%; margin: 0 auto; font-size: 10pt; }
  .cover td { border: none; padding: 5px 8px; }
  .cover td.k { text-align: right; color: #64798f; width: 40%; padding-right: 14px; }
  .cover td.v { text-align: left; font-weight: 600; color: #0f2545; }
  .cover .foot { margin-top: 30mm; font-size: 8.5pt; color: #8496a8; }
</style>
</head>
<body>
<div class="cover">
  <div class="mark"></div>
  <h1>VoltRescue</h1>
  <div class="sub">__SUBTITLE__</div>
  <div class="rule"></div>
  <table>
    <tr><td class="k">Document</td><td class="v">__TITLE__</td></tr>
    <tr><td class="k">Phase</td><td class="v">POC &mdash; Dar es Salaam pilot, Phase 1</td></tr>
    <tr><td class="k">Prepared for</td><td class="v">Mr. Menelick Erick, COO</td></tr>
    <tr><td class="k">Diagrams</td><td class="v">__DIAGRAMS__ rendered flowcharts</td></tr>
    <tr><td class="k">Generated</td><td class="v">__DATE__</td></tr>
  </table>
  <div class="foot">Generated from __SRC__ &middot; the Markdown source remains the master copy</div>
</div>
__BODY__
<script>
  mermaid.initialize({
    startOnLoad: false,
    theme: 'base',
    // Tight rank/node spacing keeps the long vertical journeys from becoming
    // so elongated that fitting them to the page shrinks the labels to nothing.
    flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis', rankSpacing: 30, nodeSpacing: 22, padding: 6 },
    themeVariables: {
      fontFamily: 'Segoe UI, Calibri, sans-serif', fontSize: '15px',
      primaryColor: '#e8f4ef', primaryBorderColor: '#1d7a5f', primaryTextColor: '#0f2545',
      lineColor: '#5b7285', secondaryColor: '#eef2f8', tertiaryColor: '#f7fafc'
    }
  });
  // Mermaid sizes flowcharts to their natural height, and the tall vertical
  // ones run past the bottom of an A4 page — which split across a page break
  // and left blanks behind. Rescale each diagram from its viewBox so it always
  // fits the printable area with its aspect ratio intact.
  function fitDiagrams() {
    // 267mm of printable height per page, less roughly 52mm for the section
    // heading, its intro line and the sub-heading that sit above a diagram.
    // Anything taller cannot share a page with its own heading, which is what
    // left a trail of near-empty heading pages through the document.
    var maxW = 172, maxH = 210;              // millimetres inside the margins
    document.querySelectorAll('.mermaid svg').forEach(function (svg) {
      var vb = svg.viewBox && svg.viewBox.baseVal;
      if (!vb || !vb.width || !vb.height) return;
      var ratio = vb.width / vb.height;
      svg.style.maxWidth = 'none';           // overrides Mermaid's inline 100%

      var hh = maxH, ww = hh * ratio;
      if (ww > maxW) { ww = maxW; hh = ww / ratio; }
      svg.setAttribute('width', ww + 'mm');
      svg.setAttribute('height', hh + 'mm');
    });
  }

  // A left-to-right chart can come out several times wider than it is tall.
  // Fitted to 172mm of page width its labels shrink to nothing, and giving it
  // a landscape page of its own wastes most of that sheet. Redrawing it
  // top-to-bottom turns the same chart into a tall, narrow one that fills a
  // portrait page at full size. Only the printed copy changes; the Markdown
  // keeps its original direction.
  function reflowWideDiagrams() {
    var redrawn = [];
    window.__shape = [];
    document.querySelectorAll('.mermaid').forEach(function (el) {
      var svg = el.querySelector('svg');
      if (!svg || !svg.viewBox || !svg.viewBox.baseVal.height) return;
      var ratio = svg.viewBox.baseVal.width / svg.viewBox.baseVal.height;
      var src = el.getAttribute('data-src') || '';
      var turned = src.replace(/(^|\n)([ \t]*(?:flowchart|graph)[ \t]+)(LR|RL)\b/, '$1$2TD');
      var can = ratio > 2.2 && turned !== src;
      window.__shape.push({ ratio: ratio, turned: can });
      if (!can) return;

      el.removeAttribute('data-processed');
      el.textContent = turned;
      redrawn.push(el);
    });
    if (!redrawn.length) return Promise.resolve(0);
    return mermaid.run({ nodes: redrawn }).then(function () { return redrawn.length; });
  }

  // The PDF is only captured once this flag flips, so a half-drawn diagram
  // can never reach the page.
  window.__diagramsReady = false;
  window.__reflowed = 0;
  // Keep each diagram's source: Mermaid overwrites the element with its SVG.
  document.querySelectorAll('.mermaid').forEach(function (el) {
    el.setAttribute('data-src', el.textContent);
  });
  mermaid.run({ querySelector: '.mermaid' })
    .then(reflowWideDiagrams)
    .then(function (n) { window.__reflowed = n; fitDiagrams(); window.__diagramsReady = true; })
    .catch(function (e) { window.__diagramError = String(e); window.__diagramsReady = true; });
</script>
</body>
</html>
'@

$page = $template.
  Replace('__TITLE__', $docTitle).
  Replace('__SUBTITLE__', $Subtitle).
  Replace('__DIAGRAMS__', "$diagrams").
  Replace('__DATE__', $generated).
  Replace('__SRC__', (Split-Path $Source -Leaf)).
  Replace('__BODY__', $html.ToString())

$htmlPath = [System.IO.Path]::ChangeExtension($Output, 'html')
[System.IO.File]::WriteAllText($htmlPath, $page, (New-Object System.Text.UTF8Encoding $false))
Write-Host "HTML built : $htmlPath  ($diagrams diagrams)"

# ---------------------------------------------------------------------------
# Print.
#
# The browser is driven over DevTools rather than with --print-to-pdf, because
# the command-line switch cannot produce a running footer. Going through the
# protocol buys two things that matter for a formal document: real "Page x of
# y" numbering, and the ability to wait for __diagramsReady instead of hoping
# a fixed time budget was long enough.
# ---------------------------------------------------------------------------
if (Test-Path $Output) { Remove-Item $Output -Force }
$profileDir = Join-Path $env:TEMP ("vr-pdf-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fileUrl = ([uri]::new($htmlPath)).AbsoluteUri

$script:cdpId = 0
function Send-Cdp($ws, [string]$method, $params) {
  $script:cdpId++
  $payload = @{ id = $script:cdpId; method = $method }
  if ($params) { $payload['params'] = $params }
  $json = $payload | ConvertTo-Json -Depth 12 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $bytes)
  if (-not $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
        [System.Threading.CancellationToken]::None).Wait(15000)) { throw "CDP send timed out ($method)" }
  return $script:cdpId
}

function Receive-Cdp($ws, [int]$wantId, [int]$timeoutSec = 120) {
  $buf = New-Object byte[] 131072
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $buf)
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $sb = New-Object System.Text.StringBuilder
    do {
      $remaining = [int]([math]::Max(1000, ($deadline - (Get-Date)).TotalMilliseconds))
      $task = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
      if (-not $task.Wait($remaining)) { throw "CDP receive timed out waiting for message $wantId" }
      $res = $task.Result
      [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count))
    } while (-not $res.EndOfMessage)
    # Events share the socket with replies, so skip anything that is not ours.
    $obj = $sb.ToString() | ConvertFrom-Json
    if ($obj.id -eq $wantId) { return $obj }
  }
  throw "CDP produced no reply to message $wantId"
}

function Invoke-Cdp($ws, [string]$method, $params, [int]$timeoutSec = 120) {
  $id = Send-Cdp $ws $method $params
  $reply = Receive-Cdp $ws $id $timeoutSec
  if ($reply.error) { throw "CDP $method failed: $($reply.error.message)" }
  return $reply.result
}

$port = Get-Random -Minimum 9300 -Maximum 9890
$launch = @(
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-extensions', '--disable-sync',
  "--user-data-dir=$profileDir", "--remote-debugging-port=$port", 'about:blank'
)

Write-Host "Printing   : via $(Split-Path $edge -Leaf) (headless, DevTools)"
$proc = Start-Process -FilePath $edge -ArgumentList $launch -PassThru -WindowStyle Hidden
$ws = $null
try {
  # Wait for the debugging endpoint to come up.
  $target = $null
  for ($n = 0; $n -lt 60; $n++) {
    Start-Sleep -Milliseconds 400
    try {
      $list = Invoke-RestMethod "http://127.0.0.1:$port/json/list" -TimeoutSec 3
      $target = @($list | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl }) | Select-Object -First 1
      if ($target) { break }
    } catch { }
  }
  if (-not $target) { throw "The browser never exposed a DevTools page target on port $port." }

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  if (-not $ws.ConnectAsync([uri]$target.webSocketDebuggerUrl,
        [System.Threading.CancellationToken]::None).Wait(15000)) { throw "Could not open the DevTools socket." }

  Invoke-Cdp $ws 'Page.enable' @{} | Out-Null
  Invoke-Cdp $ws 'Page.navigate' @{ url = $fileUrl } | Out-Null

  # Poll the flag the page sets once Mermaid has drawn and rescaled everything.
  $ready = $false
  for ($n = 0; $n -lt 100; $n++) {
    Start-Sleep -Milliseconds 300
    $r = Invoke-Cdp $ws 'Runtime.evaluate' @{ expression = 'window.__diagramsReady === true'; returnByValue = $true }
    if ($r.result.value -eq $true) { $ready = $true; break }
  }
  if (-not $ready) { Write-Warning "Diagrams did not report ready in 30s; printing anyway." }

  $err = Invoke-Cdp $ws 'Runtime.evaluate' @{ expression = 'window.__diagramError || ""'; returnByValue = $true }
  if ($err.result.value) { Write-Warning "Mermaid reported: $($err.result.value)" }

  $drawn = Invoke-Cdp $ws 'Runtime.evaluate' @{ expression = 'document.querySelectorAll(".mermaid svg").length'; returnByValue = $true }
  Write-Host "Diagrams   : $($drawn.result.value) of $diagrams drawn as vector graphics"
  if ([int]$drawn.result.value -lt $diagrams) { Write-Warning "Some diagrams did not render." }

  $flow = Invoke-Cdp $ws 'Runtime.evaluate' @{ expression = 'JSON.stringify(window.__shape || [])'; returnByValue = $true }
  $shape = $flow.result.value | ConvertFrom-Json
  $turned = @($shape | Where-Object { $_.turned }).Count
  Write-Host ("Shapes     : " + (($shape | ForEach-Object {
    "{0}{1}" -f ([math]::Round($_.ratio, 2)), $(if ($_.turned) { '*' } else { '' }) }) -join ', '))
  if ($turned) { Write-Host "Reflowed   : $turned wide chart(s) redrawn top-to-bottom for print" }

  $footer = @'
<div style="width:100%;font-size:7.5pt;font-family:'Segoe UI',sans-serif;color:#8496a8;
            padding:0 16mm;display:flex;justify-content:space-between;">
  <span>VoltRescue &mdash; Business Process Flow &amp; Flowchart Guide</span>
  <span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span>
</div>
'@

  # Page geometry comes from the stylesheet's @page rules, which is what lets a
  # single wide diagram sit on a landscape page inside a portrait document.
  $pdf = Invoke-Cdp $ws 'Page.printToPDF' @{
    printBackground      = $true
    preferCSSPageSize    = $true
    displayHeaderFooter  = $true
    headerTemplate       = '<span></span>'
    footerTemplate       = $footer
  } 180

  [System.IO.File]::WriteAllBytes($Output, [Convert]::FromBase64String($pdf.data))
}
finally {
  if ($ws) { try { $ws.Dispose() } catch { } }
  if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
  Start-Sleep -Milliseconds 300
  Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Output)) { throw "No PDF was produced." }

$size = [math]::Round((Get-Item $Output).Length / 1KB, 1)
if (-not $KeepHtml) { Remove-Item $htmlPath -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "PDF ready  : $Output" -ForegroundColor Green
Write-Host "Size       : $size KB"
