<#
install-windows.ps1
Instala dependências e clona repos para o toolkit (dirsearch, XSStrike, SecLists).
Rode como Administrador (ou confirme elevação quando solicitado).
#>

# Saída colorida simples
function Info($msg){ Write-Host "[i] $msg" -ForegroundColor Cyan }
function Ok($msg){ Write-Host "[+] $msg" -ForegroundColor Green }
function Warn($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err($msg){ Write-Host "[-] $msg" -ForegroundColor Red }

# Diretórios
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SecListsDir = Join-Path $ScriptDir "seclists"
$WordlistsDir = Join-Path $ScriptDir "wordlists"
$DirsearchDir = Join-Path $ScriptDir "dirsearch"
$XSDir = Join-Path $ScriptDir "XSStrike"

# Utils
function CommandExists($cmd){
  $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

# Prefer winget, fallback to choco if winget ausente
$pkgManager = if (CommandExists winget) { "winget" } elseif (CommandExists choco) { "choco" } else { "" }

if ($pkgManager -eq "") {
  Warn "Nenhum gerenciador encontrado (winget/choco). Você precisará instalar manualmente: git, curl, python, go, nmap, jq."
} else {
  Info "Usando pacote: $pkgManager"
}

# Function to install packages (winget/choco)
function InstallPkgs([string[]] $pkgs){
  if ($pkgManager -eq "winget"){
    foreach ($p in $pkgs){
      Info "Tentando winget install $p"
      winget install --silent --accept-package-agreements --accept-source-agreements $p 2>$null || Warn "winget install falhou para $p"
    }
  } elseif ($pkgManager -eq "choco"){
    foreach ($p in $pkgs){
      Info "Tentando choco install $p -y"
      choco install $p -y 2>$null || Warn "choco install falhou para $p"
    }
  }
}

# Pacotes básicos
$basic = @()
# nomes diferentes por gerenciador: winget usa IDs (ex: Git.Git), choco usa nomes simples.
if ($pkgManager -eq "winget"){
  $basic = @("Git.Git","Python.Python.3","GnuWin32.Curl","Nmap.Nmap","GoLang.Go","GnuWin32.Jq")
} elseif ($pkgManager -eq "choco"){
  $basic = @("git","python","curl","nmap","golang","jq")
}
if ($basic.Count -gt 0){
  InstallPkgs $basic
}

# Ensure git present
if (-not (CommandExists git)) { Err "git não encontrado — instale manualmente e re-run." ; exit 1 }

# Clone helpers
function GitCloneOrUpdate($url, $dest){
  if (Test-Path (Join-Path $dest ".git")){
    Info "Atualizando $dest..."
    git -C $dest pull --ff-only 2>$null || Warn "git pull falhou para $dest"
  } elseif (Test-Path $dest){
    Warn "$dest existe mas não é um repositório git. Pulando clone."
  } else {
    Info "Clonando $url -> $dest"
    git clone --depth 1 $url $dest 2>$null || Warn "Falha ao clonar $url"
  }
}

# Clonar repositórios
GitCloneOrUpdate "https://github.com/maurosoria/dirsearch.git" $DirsearchDir
GitCloneOrUpdate "https://github.com/s0md3v/XSStrike.git" $XSDir
GitCloneOrUpdate "https://github.com/danielmiessler/SecLists.git" $SecListsDir

# pip installs for XSStrike / dirsearch
if (CommandExists pip3 -or CommandExists pip) {
  $pip = if (CommandExists pip3) { "pip3" } else { "pip" }
  if (Test-Path (Join-Path $XSDir "requirements.txt")){
    Info "Instalando dependências do XSStrike via $pip..."
    & $pip install -r (Join-Path $XSDir "requirements.txt") 2>$null || Warn "pip install requirements falhou"
  }
} else { Warn "pip não encontrado; instale pacotes Python manualmente (requests etc)." }

# go-based tools (ffuf, subfinder)
if (CommandExists go){
  $gobin = (go env GOBIN) 2>$null
  if ([string]::IsNullOrEmpty($gobin)) { $gopath = (go env GOPATH); $gobin = Join-Path $gopath "bin" }
  Info "Instalando ffuf e subfinder via go install..."
  & go install github.com/ffuf/ffuf@latest 2>$null || Warn "go install ffuf falhou"
  & go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>$null || Warn "go install subfinder falhou"
  Ok "Ferramentas go instaladas (verifique se $gobin está no PATH)"
} else {
  Warn "go não encontrado — pulei 'go install'. Instale go para obter ffuf/subfinder via go."
}

Ok "Instalação concluída (ou realizada parcialmente). Verifique mensagens acima."
Write-Host ""
Write-Host "Resumo:"
Write-Host " - dirsearch: $DirsearchDir"
Write-Host " - XSStrike: $XSDir"
Write-Host " - SecLists: $SecListsDir"
Write-Host "Se algum bin não estiver no PATH, adicione o diretório do go bin (ex: $env:USERPROFILE\go\bin) ao PATH."

