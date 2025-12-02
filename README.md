# 📁 Organizador de Downloads com Exclusão Segura

Script PowerShell profissional para organização automática de arquivos na pasta Downloads com recursos de exclusão segura de nível forense.

## ✨ Características

- 🗂️ **Organização Inteligente**: Classifica automaticamente arquivos em 10 categorias
- 🔒 **Exclusão Segura**: Sobrescreve dados 7 vezes seguindo padrões forenses (DoD 5220.22-M)
- 📊 **Estatísticas Detalhadas**: Relatórios completos de execução
- 🛡️ **Thread-Safe**: Logging seguro para execução concorrente
- 🧪 **Modo Simulação**: Teste operações com `-WhatIf`
- 📝 **Logs Automáticos**: Histórico de 30 dias com limpeza automática

## 🚀 Requisitos

- **PowerShell 7.0+** ([Download](https://github.com/PowerShell/PowerShell/releases))
- **Windows 10/11** ou **Windows Server 2019+**
- Permissões de escrita na pasta Downloads

## 📥 Instalação

1. Clone ou baixe o repositório:
```powershell
git clone https://github.com/seu-usuario/downloads-organizer.git
cd downloads-organizer
```

2. Verifique a versão do PowerShell:
```powershell
$PSVersionTable.PSVersion
# Deve ser 7.0 ou superior
```

## 🎯 Uso Básico

### Execução Padrão
```powershell
.\automacao.ps1
```

### Modo Simulação (Teste sem modificar arquivos)
```powershell
.\automacao.ps1 -WhatIf
```

### Organizar sem Excluir Pastas
```powershell
.\automacao.ps1 -SkipCleanup
```

### Combinação de Parâmetros
```powershell
.\automacao.ps1 -WhatIf -SkipCleanup
```

## 📂 Categorias de Organização

| Categoria | Extensões |
|-----------|-----------|
| 🖼️ **Imagens** | `.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp`, `.svg`, `.webp`, `.ico`, `.tiff`, `.heic` |
| 📄 **Documentos** | `.pdf`, `.doc`, `.docx`, `.odt`, `.rtf`, `.tex`, `.txt`, `.wpd` |
| 📊 **Planilhas** | `.xls`, `.xlsx`, `.csv`, `.ods`, `.xlsm`, `.xlsb` |
| 📽️ **Apresentações** | `.ppt`, `.pptx`, `.odp`, `.key` |
| 💿 **Instaladores** | `.exe`, `.msi`, `.dmg`, `.pkg`, `.deb`, `.rpm`, `.appimage` |
| 📦 **Compactados** | `.zip`, `.rar`, `.7z`, `.tar`, `.gz`, `.bz2`, `.xz`, `.iso` |
| 🎬 **Vídeos** | `.mp4`, `.avi`, `.mkv`, `.mov`, `.wmv`, `.flv`, `.webm`, `.m4v` |
| 🎵 **Áudio** | `.mp3`, `.wav`, `.flac`, `.aac`, `.ogg`, `.wma`, `.m4a`, `.opus` |
| 💻 **Código** | `.py`, `.js`, `.java`, `.cpp`, `.c`, `.cs`, `.html`, `.css`, `.json`, `.xml`, `.ps1` |
| 📌 **Outros** | Demais extensões não categorizadas |

## 🔐 Exclusão Segura - Detalhes Técnicos

O script implementa exclusão forense de dados em **7 passes**:

1. **Passe 1**: Dados aleatórios (RNG criptográfico)
2. **Passe 2**: Zeros (`0x00`)
3. **Passe 3**: Uns (`0xFF`)
4. **Passe 4**: Dados aleatórios
5. **Passe 5**: Padrão alternado (`0xAA`)
6. **Passe 6**: Padrão complementar (`0x55`)
7. **Passe 7**: Dados aleatórios finais

### Recursos Adicionais de Segurança

- ✅ Renomeação aleatória (3 iterações)
- ✅ Alteração de timestamps
- ✅ Flush direto em disco (`WriteThrough`)
- ✅ Processamento em chunks de 64KB

## 📋 Funcionamento

### Etapa 1: Criação de Estrutura
Cria as pastas de categorias caso não existam.

### Etapa 2: Organização de Arquivos
- Classifica arquivos por extensão
- Move para pasta apropriada
- Resolve conflitos de nomes automaticamente

### Etapa 3: Limpeza de Pastas (Opcional)
- Remove pastas não reconhecidas
- Aplica exclusão segura em todo conteúdo

## 📊 Exemplo de Saída

```
╔═══════════════════════════════════════════════╗
             📊 RESUMO DA EXECUÇÃO
╚═══════════════════════════════════════════════╝

[2024-12-01 14:32:15] [INFO] Arquivos organizados: 47
[2024-12-01 14:32:15] [INFO] Pastas removidas: 3
[2024-12-01 14:32:15] [INFO] Dados processados: 2.45 GB
[2024-12-01 14:32:15] [INFO] Erros encontrados: 0
[2024-12-01 14:32:15] [INFO] Tempo de execução: 01:23.456

📄 Log completo: C:\Users\...\DownloadsOrganizer\log_2024-12-01_143215.txt
╚═══════════════════════════════════════════════
```

## 📁 Estrutura de Logs

```
%LocalAppData%\DownloadsOrganizer\
├── log_2024-12-01_143215.txt
├── log_2024-11-30_091045.txt
└── ...
```

Logs mais antigos que 30 dias são removidos automaticamente.

## ⚙️ Personalização

### Modificar Categorias

Edite o hashtable `$script:CategoryMap` no arquivo:

```powershell
$script:CategoryMap = @{
    MinhaCategoria = [string[]]@('.ext1', '.ext2', '.ext3')
    # ...
}
```

### Ajustar Número de Passes de Exclusão

```powershell
$script:Config = [PSCustomObject]@{
    # ...
    SecureWipes = 7  # Altere aqui (3-35 passes)
    # ...
}
```

### Alterar Tamanho de Chunk

```powershell
$script:Config = [PSCustomObject]@{
    # ...
    ChunkSize = 64KB  # Opções: 32KB, 128KB, 256KB, etc.
    # ...
}
```

## 🤝 Automação com Agendador de Tarefas

### Via PowerShell

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-File C:\caminho\automacao.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 2AM

Register-ScheduledTask -TaskName "OrganizarDownloads" `
    -Action $action -Trigger $trigger -Description "Organização diária da pasta Downloads"
```

### Via Interface Gráfica

1. Abra **Agendador de Tarefas**
2. Criar Tarefa Básica
3. Ação: **Iniciar programa**
4. Programa: `pwsh.exe`
5. Argumentos: `-File "C:\caminho\automacao.ps1"`

## ⚠️ Avisos Importantes

- ⚡ **Exclusão é irreversível**: Arquivos removidos não podem ser recuperados
- 🧪 **Teste primeiro**: Use `-WhatIf` antes da primeira execução
- 💾 **Backup**: Mantenha backups de arquivos importantes
- 🔒 **Permissões**: Garanta acesso de escrita na pasta Downloads
- ⏱️ **Tempo de execução**: Exclusão segura é intensiva e pode levar tempo

## 🐛 Solução de Problemas

### Erro: "Script não pode ser executado"

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Erro: "PowerShell 7.0 necessário"

Instale o PowerShell Core 7+:
```powershell
winget install Microsoft.PowerShell
```

### Arquivos não são movidos

- Verifique se há arquivos abertos em outros programas
- Execute como Administrador se necessário
- Confira permissões da pasta Downloads

## 📜 Licença

Este projeto é de código aberto sob a licença MIT.

## 👨‍💻 Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para:

1. Fazer fork do projeto
2. Criar branch para sua feature (`git checkout -b feature/MinhaFeature`)
3. Commit suas mudanças (`git commit -m 'Adiciona MinhaFeature'`)
4. Push para o branch (`git push origin feature/MinhaFeature`)
5. Abrir Pull Request

## 📞 Suporte

- 🐛 **Issues**: Reporte bugs na aba Issues do GitHub
- 💬 **Discussões**: Use Discussions para perguntas
- 📧 **Email**: contato@exemplo.com

---

**Desenvolvido com ❤️ para manter sua pasta Downloads sempre organizada**