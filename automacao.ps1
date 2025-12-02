#Requires -Version 7.0
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Security.Cryptography

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$SkipCleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ====================================================================
# CONFIGURAÇÕES
# ====================================================================

$script:Config = [PSCustomObject]@{
    DownloadsFolder = [Environment]::GetFolderPath('UserProfile') | Join-Path -ChildPath 'Downloads'
    LogFolder       = [Environment]::GetFolderPath('LocalApplicationData') | Join-Path -ChildPath 'DownloadsOrganizer'
    LogFile         = $null
    SecureWipes     = 7
    ChunkSize       = 64KB
}

$script:Config.LogFile = Join-Path $script:Config.LogFolder "log_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"

# Mapeamento de extensões
$script:CategoryMap = @{
    Imagens       = [string[]]@('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.ico', '.tiff', '.heic')
    Documentos    = [string[]]@('.pdf', '.doc', '.docx', '.odt', '.rtf', '.tex', '.txt', '.wpd')
    Planilhas     = [string[]]@('.xls', '.xlsx', '.csv', '.ods', '.xlsm', '.xlsb')
    Apresentações = [string[]]@('.ppt', '.pptx', '.odp', '.key')
    Instaladores  = [string[]]@('.exe', '.msi', '.dmg', '.pkg', '.deb', '.rpm', '.appimage')
    Compactados   = [string[]]@('.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.iso')
    Videos        = [string[]]@('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v')
    Audio         = [string[]]@('.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus')
    Codigo        = [string[]]@('.py', '.js', '.java', '.cpp', '.c', '.cs', '.html', '.css', '.json', '.xml', '.ps1')
    Outros        = [string[]]@()
}

# Lookup table
$script:ExtensionLookup = @{}
foreach ($category in $script:CategoryMap.Keys) {
    foreach ($ext in $script:CategoryMap[$category]) {
        $script:ExtensionLookup[$ext] = $category
    }
}

$script:FoldersToKeep = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($k in $script:CategoryMap.Keys) {
    [void]$script:FoldersToKeep.Add([string]$k)
}

# Estatísticas CORRIGIDAS - tipos simples para script single-threaded
$script:Stats = [PSCustomObject]@{
    FilesOrganized = 0  # ✅ Número simples
    FoldersDeleted = 0
    BytesProcessed = 0
    Errors         = [List[string]]::new()
    StartTime      = [DateTime]::Now
    EndTime        = $null
}

# Mutex global para logging (criado uma única vez)
$script:LogMutex = [System.Threading.Mutex]::new($false, 'DownloadsOrganizerLogMutex')

# ====================================================================
# FUNÇÕES DE LOGGING
# ====================================================================

function Initialize-Environment {
    if (-not (Test-Path $script:Config.LogFolder)) {
        [Directory]::CreateDirectory($script:Config.LogFolder) | Out-Null
    }
    
    Get-ChildItem -Path $script:Config.LogFolder -Filter "log_*.txt" -File |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        'DEBUG'   { 'Gray' }
        default   { 'White' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # File output thread-safe (usando mutex global)
    try {
        $null = $script:LogMutex.WaitOne()
        [File]::AppendAllText($script:Config.LogFile, "$logEntry`n", [Text.Encoding]::UTF8)
    }
    finally {
        $script:LogMutex.ReleaseMutex()
    }
}

# ====================================================================
# EXCLUSÃO SEGURA FORENSE
# ====================================================================

function Invoke-SecureWipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) { return }
    
    $item = Get-Item -Path $Path -Force
    
    if ($item.PSIsContainer) {
        Remove-SecureDirectory -Path $Path
    }
    else {
        Remove-SecureFile -Path $Path
    }
}

function Remove-SecureFile {
    [CmdletBinding()]
    param([string]$Path)
    
    try {
        $file = [FileInfo]::new($Path)
        $originalSize = $file.Length
        
        if ($originalSize -eq 0) {
            Remove-Item $Path -Force
            return
        }
        
        $file.Attributes = [FileAttributes]::Normal
        
        $stream = [FileStream]::new(
            $Path,
            [FileMode]::Open,
            [FileAccess]::Write,
            [FileShare]::None,
            $script:Config.ChunkSize,
            [FileOptions]::WriteThrough -bor [FileOptions]::SequentialScan
        )
        
        try {
            $buffer = [byte[]]::new([Math]::Min($originalSize, $script:Config.ChunkSize))
            
            $patterns = @(
                { param($buf) [RNGCryptoServiceProvider]::new().GetBytes($buf) },
                { param($buf) [Array]::Fill($buf, [byte]0x00) },
                { param($buf) [Array]::Fill($buf, [byte]0xFF) },
                { param($buf) [RNGCryptoServiceProvider]::new().GetBytes($buf) },
                { param($buf) [Array]::Fill($buf, [byte]0xAA) },
                { param($buf) [Array]::Fill($buf, [byte]0x55) },
                { param($buf) [RNGCryptoServiceProvider]::new().GetBytes($buf) }
            )
            
            foreach ($pattern in $patterns) {
                $stream.Position = 0
                $remaining = $originalSize
                
                while ($remaining -gt 0) {
                    $bytesToWrite = [Math]::Min($remaining, $buffer.Length)
                    & $pattern $buffer
                    $stream.Write($buffer, 0, $bytesToWrite)
                    $remaining -= $bytesToWrite
                }
                
                $stream.Flush($true)
            }
        }
        finally {
            $stream.Dispose()
        }
        
        [File]::WriteAllBytes($Path, [byte[]]::new(0))
        
        $dir = $file.DirectoryName
        $tempPath = $Path
        
        for ($i = 0; $i -lt 3; $i++) {
            $randomName = [Path]::GetRandomFileName()
            $newPath = Join-Path $dir $randomName
            Move-Item -Path $tempPath -Destination $newPath -Force
            $tempPath = $newPath
        }
        
        $now = [DateTime]::Now.AddDays(-365)
        $fileToDelete = [FileInfo]::new($tempPath)
        $fileToDelete.CreationTime = $now
        $fileToDelete.LastWriteTime = $now
        $fileToDelete.LastAccessTime = $now
        
        Remove-Item -Path $tempPath -Force
        
        Write-Log "🗑️ Arquivo '$($file.Name)' ($(Format-FileSize $originalSize)) apagado com segurança" 'SUCCESS'
        $script:Stats.BytesProcessed += $originalSize
    }
    catch {
        $script:Stats.Errors.Add("Erro ao apagar '$Path': $($_.Exception.Message)")
        Write-Log "Erro ao apagar arquivo '$Path': $($_.Exception.Message)" 'ERROR'
    }
}

function Remove-SecureDirectory {
    [CmdletBinding()]
    param([string]$Path)
    
    try {
        Get-ChildItem -Path $Path -Force -ErrorAction Stop | ForEach-Object {
            if ($_.PSIsContainer) {
                Remove-SecureDirectory -Path $_.FullName
            }
            else {
                Remove-SecureFile -Path $_.FullName
            }
        }
        
        $parent = Split-Path $Path -Parent
        $randomName = [Path]::GetRandomFileName()
        $newPath = Join-Path $parent $randomName
        
        Rename-Item -Path $Path -NewName $randomName -Force
        
        $dir = [DirectoryInfo]::new($newPath)
        $now = [DateTime]::Now.AddDays(-365)
        $dir.CreationTime = $now
        $dir.LastWriteTime = $now
        $dir.LastAccessTime = $now
        
        Remove-Item -Path $newPath -Force -Recurse
        
        Write-Log "✅ Pasta apagada com segurança" 'SUCCESS'
        $script:Stats.FoldersDeleted++
    }
    catch {
        $script:Stats.Errors.Add("Erro ao apagar pasta '$Path': $($_.Exception.Message)")
        Write-Log "Erro ao apagar pasta '$Path': $($_.Exception.Message)" 'ERROR'
    }
}

# ====================================================================
# ORGANIZAÇÃO DE ARQUIVOS
# ====================================================================

function Get-FileCategory {
    [CmdletBinding()]
    param([string]$Extension)
    
    $normalized = $Extension.ToLowerInvariant()
    
    if ($script:ExtensionLookup.ContainsKey($normalized)) {
        return $script:ExtensionLookup[$normalized]
    }
    
    return 'Outros'
}

function Move-FilesToCategories {
    [CmdletBinding()]
    param()
    
    Write-Log "ETAPA 2: Organizando arquivos" 'INFO'
    
    $files = Get-ChildItem -Path $script:Config.DownloadsFolder -File -Force |
        Where-Object { -not $_.PSIsContainer }
    
    if ((@($files)).Count -eq 0) {
        Write-Log "Nenhum arquivo para organizar" 'INFO'
        return
    }
    
    Write-Log "Encontrados $((@($files)).Count) arquivos para processar" 'INFO'
    
    $filesByCategory = $files | Group-Object { Get-FileCategory -Extension $_.Extension }
    
    foreach ($group in $filesByCategory) {
        $category = $group.Name
        $targetPath = Join-Path $script:Config.DownloadsFolder $category
        
        foreach ($file in $group.Group) {
            try {
                $destination = Join-Path $targetPath $file.Name
                
                if (Test-Path $destination) {
                    $baseName = [Path]::GetFileNameWithoutExtension($file.Name)
                    $extension = $file.Extension
                    $counter = 1
                    
                    do {
                        $newName = "${baseName}_${counter}${extension}"
                        $destination = Join-Path $targetPath $newName
                        $counter++
                    } while (Test-Path $destination)
                }
                
                if ($WhatIf) {
                    Write-Log "[WHATIF] Moveria '$($file.Name)' → '$category'" 'DEBUG'
                }
                else {
                    Move-Item -Path $file.FullName -Destination $destination -Force
                    Write-Log "📦 '$($file.Name)' → '$category'" 'SUCCESS'
                }
                
                # ✅ CORRETO: Incremento simples
                $script:Stats.FilesOrganized++
            }
            catch {
                $script:Stats.Errors.Add("Erro ao mover '$($file.Name)': $($_.Exception.Message)")
                Write-Log "Erro ao mover '$($file.Name)': $($_.Exception.Message)" 'ERROR'
            }
        }
    }
}

# ====================================================================
# LIMPEZA DE PASTAS
# ====================================================================

function Remove-UnknownFolders {
    [CmdletBinding()]
    param()
    
    if ($SkipCleanup) {
        Write-Log "Limpeza de pastas ignorada (parâmetro -SkipCleanup)" 'INFO'
        return
    }
    
    Write-Log "ETAPA 3: Removendo pastas não reconhecidas" 'INFO'
    
    $folders = Get-ChildItem -Path $script:Config.DownloadsFolder -Directory -Force |
        Where-Object { -not $script:FoldersToKeep.Contains($_.Name) }
    
    if ((@($folders)).Count -eq 0) {
        Write-Log "Nenhuma pasta não reconhecida encontrada" 'INFO'
        return
    }
    
    $foldersCount = (@($folders)).Count
    Write-Log "Encontradas $($foldersCount) pastas para remoção" 'WARNING'
    
    foreach ($folder in $folders) {
        if ($WhatIf) {
            Write-Log "[WHATIF] Removeria pasta: '$($folder.Name)'" 'DEBUG'
        }
        else {
            Write-Log "🗑️ Removendo pasta: '$($folder.Name)'" 'WARNING'
            Invoke-SecureWipe -Path $folder.FullName
        }
    }
}

# ====================================================================
# UTILITÁRIOS
# ====================================================================

function Format-FileSize {
    param([long]$Bytes)
    
    $sizes = @('B', 'KB', 'MB', 'GB', 'TB')
    $order = 0
    $value = $Bytes
    
    while ($value -ge 1024 -and $order -lt $sizes.Count - 1) {
        $value = $value / 1024
        $order++
    }
    
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

function Show-Summary {
    $script:Stats.EndTime = [DateTime]::Now
    $duration = $script:Stats.EndTime - $script:Stats.StartTime
    
    Write-Host "`n╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "             📊 RESUMO DA EXECUÇÃO" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Log "Arquivos organizados: $($script:Stats.FilesOrganized)" 'INFO'
    Write-Log "Pastas removidas: $($script:Stats.FoldersDeleted)" 'INFO'
    Write-Log "Dados processados: $(Format-FileSize $script:Stats.BytesProcessed)" 'INFO'
    Write-Log "Erros encontrados: $($script:Stats.Errors.Count)" 'INFO'
    Write-Log "Tempo de execução: $($duration.ToString('mm\:ss\.fff'))" 'INFO'
    
    if ($script:Stats.Errors.Count -gt 0) {
        Write-Host "`n⚠️ Detalhes dos erros:" -ForegroundColor Yellow
        $script:Stats.Errors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    }
    
    Write-Host "`n📄 Log completo: $($script:Config.LogFile)" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

# ====================================================================
# EXECUÇÃO PRINCIPAL
# ====================================================================

function Invoke-DownloadsOrganizer {
    try {
        Initialize-Environment
        
        Write-Host "`n🛠️ Organizador de Downloads - Versão 2.0" -ForegroundColor Yellow
        Write-Log "╔══ INICIANDO ORGANIZAÇÃO ══╗" 'INFO'
        Write-Log "Pasta: $($script:Config.DownloadsFolder)" 'INFO'
        Write-Log "Modo: $(if($WhatIf){'SIMULAÇÃO'}else{'PRODUÇÃO'})" 'INFO'
        
        if (-not (Test-Path $script:Config.DownloadsFolder)) {
            throw "Pasta Downloads não encontrada: $($script:Config.DownloadsFolder)"
        }
        
        # ETAPA 1: Criar estrutura
        Write-Log "ETAPA 1: Criando estrutura de pastas" 'INFO'
        foreach ($category in $script:CategoryMap.Keys) {
            $folderPath = Join-Path $script:Config.DownloadsFolder $category
            if (-not (Test-Path $folderPath)) {
                New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
                Write-Log "📂 Pasta '$category' criada" 'INFO'
            }
        }
        
        # ETAPA 2: Organizar arquivos
        Move-FilesToCategories
        
        # ETAPA 3: Limpar pastas
        Remove-UnknownFolders
        
        # Resumo
        Show-Summary
        
        Write-Host "✅ Organização concluída com sucesso!`n" -ForegroundColor Green
    }
    catch {
        Write-Log "ERRO CRÍTICO: $($_.Exception.Message)" 'ERROR'
        Write-Log $_.ScriptStackTrace 'ERROR'
        throw
    }
    finally {
        # Liberar mutex
        if ($script:LogMutex) {
            $script:LogMutex.Dispose()
        }
    }
}

# Executar
Invoke-DownloadsOrganizer