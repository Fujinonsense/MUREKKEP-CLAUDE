param([string[]]$Files)
# Crude Swift bracket balance check: skips comments, string literals (incl. """ blocks and \( ) interpolation).
foreach ($f in $Files) {
    # .NET resolves relative paths against the process folder, not the PowerShell location.
    $f = (Resolve-Path -LiteralPath $f -ErrorAction Stop).Path
    $s = [IO.File]::ReadAllText($f)
    $stack = New-Object System.Collections.Generic.List[object]
    $i = 0; $line = 1; $n = $s.Length; $err = $null
    # string state stack: each entry is 'S' (single-line) or 'M' (multi-line); interpolation pushes '(' marker with depth
    $mode = New-Object System.Collections.Generic.List[string]  # 'code','str','mstr'
    $mode.Add('code')
    $interp = New-Object System.Collections.Generic.List[int]   # paren depth when interpolation started
    $depth = 0
    while ($i -lt $n) {
        $c = $s[$i]
        if ($c -eq "`n") { $line++ }
        $m = $mode[$mode.Count - 1]
        if ($m -eq 'code') {
            if ($c -eq '/' -and $i + 1 -lt $n -and $s[$i + 1] -eq '/') { while ($i -lt $n -and $s[$i] -ne "`n") { $i++ }; continue }
            if ($c -eq '/' -and $i + 1 -lt $n -and $s[$i + 1] -eq '*') { $i += 2; while ($i + 1 -lt $n -and -not ($s[$i] -eq '*' -and $s[$i + 1] -eq '/')) { if ($s[$i] -eq "`n") { $line++ }; $i++ }; $i += 2; continue }
            if ($c -eq '"') {
                if ($i + 2 -lt $n -and $s[$i + 1] -eq '"' -and $s[$i + 2] -eq '"') { $mode.Add('mstr'); $i += 3; continue }
                $mode.Add('str'); $i++; continue
            }
            if ('({['.Contains($c)) { $stack.Add(@($c, $line)); $depth++ }
            elseif (')}]'.Contains($c)) {
                if ($interp.Count -gt 0 -and $c -eq ')' -and $depth -eq $interp[$interp.Count - 1]) {
                    $interp.RemoveAt($interp.Count - 1); $mode.RemoveAt($mode.Count - 1); $i++; continue
                }
                if ($stack.Count -eq 0) { $err = "unexpected $c at line $line"; break }
                $open = $stack[$stack.Count - 1][0]
                $want = @{ '(' = ')'; '{' = '}'; '[' = ']' }[[string]$open]
                if ($want -ne [string]$c) { $err = "mismatch $open (line $($stack[$stack.Count - 1][1])) vs $c at line $line"; break }
                $stack.RemoveAt($stack.Count - 1); $depth--
            }
            $i++; continue
        }
        # inside string
        if ($c -eq '\') {
            if ($i + 1 -lt $n -and $s[$i + 1] -eq '(') { $interp.Add($depth); $mode.Add('code'); $i += 2; continue }
            $i += 2; continue
        }
        if ($m -eq 'str' -and $c -eq '"') { $mode.RemoveAt($mode.Count - 1); $i++; continue }
        if ($m -eq 'str' -and $c -eq "`n") { $err = "unterminated string at line $($line - 1)"; break }
        if ($m -eq 'mstr' -and $c -eq '"' -and $i + 2 -lt $n -and $s[$i + 1] -eq '"' -and $s[$i + 2] -eq '"') { $mode.RemoveAt($mode.Count - 1); $i += 3; continue }
        $i++
    }
    if (-not $err -and $stack.Count -gt 0) { $err = "unclosed $($stack[$stack.Count - 1][0]) from line $($stack[$stack.Count - 1][1])" }
    if (-not $err -and $mode.Count -ne 1) { $err = "string/interpolation not closed" }
    $name = Split-Path $f -Leaf
    if ($err) { "FAIL $name : $err" } else { "ok   $name" }
}
