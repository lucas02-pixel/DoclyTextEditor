-- Janela nativa de "escolher arquivo".
-- O LÖVE não tem uma, então chamamos o sistema operacional:
--   Windows: PowerShell (OpenFileDialog), sem abrir janela de terminal
--   macOS:   osascript
--   Linux:   zenity ou kdialog
--
-- FileDialog.pick("image" | "file") retorna:
--   { path, name, size, data }  (data = bytes do arquivo, só para imagens)
--   nil, "cancelled"            (o usuário fechou a janela)
--   nil, "unavailable"          (não foi possível abrir a janela)

local FileDialog = {}
local utf8 = require("utf8")

local function toUtf16LE(text)
    local bytes = {}

    for _, codepoint in utf8.codes(text) do
        if codepoint < 0x10000 then
            bytes[#bytes + 1] = string.char(
                codepoint % 0x100,
                math.floor(codepoint / 0x100)
            )
        else
            local value = codepoint - 0x10000
            local high = 0xD800 + math.floor(value / 0x400)
            local low = 0xDC00 + value % 0x400

            bytes[#bytes + 1] = string.char(
                high % 0x100,
                math.floor(high / 0x100),
                low % 0x100,
                math.floor(low / 0x100)
            )
        end
    end

    return table.concat(bytes)
end

-- Windows: CreateProcess sem janela (ffi) -------------------------------

-- Nomes com prefixo "docly_" para não colidir com outras declarações
local CDEF = [[
typedef struct {
    uint32_t nLength;
    void *lpSecurityDescriptor;
    int32_t bInheritHandle;
} docly_SECURITY_ATTRIBUTES;

typedef struct {
    uint32_t cb;
    char *lpReserved;
    char *lpDesktop;
    char *lpTitle;
    uint32_t dwX;
    uint32_t dwY;
    uint32_t dwXSize;
    uint32_t dwYSize;
    uint32_t dwXCountChars;
    uint32_t dwYCountChars;
    uint32_t dwFillAttribute;
    uint32_t dwFlags;
    uint16_t wShowWindow;
    uint16_t cbReserved2;
    uint8_t *lpReserved2;
    void *hStdInput;
    void *hStdOutput;
    void *hStdError;
} docly_STARTUPINFOA;

typedef struct {
    void *hProcess;
    void *hThread;
    uint32_t dwProcessId;
    uint32_t dwThreadId;
} docly_PROCESS_INFORMATION;

int CreatePipe(void **hReadPipe, void **hWritePipe,
    docly_SECURITY_ATTRIBUTES *attributes, uint32_t size);
int SetHandleInformation(void *handle, uint32_t mask, uint32_t flags);
void *CreateFileA(const char *name, uint32_t access, uint32_t share,
    docly_SECURITY_ATTRIBUTES *attributes, uint32_t disposition,
    uint32_t flags, void *template);
int CreateProcessA(const char *application, char *commandLine,
    void *processAttributes, void *threadAttributes, int inheritHandles,
    uint32_t creationFlags, void *environment, const char *directory,
    docly_STARTUPINFOA *startup, docly_PROCESS_INFORMATION *info);
int ReadFile(void *handle, void *buffer, uint32_t size,
    uint32_t *read, void *overlapped);
uint32_t WaitForSingleObject(void *handle, uint32_t milliseconds);
int GetExitCodeProcess(void *handle, uint32_t *code);
int CloseHandle(void *handle);
]]

local ffi = nil
local kernel32 = nil
local ffiTried = false

local function initFfi()
    if ffiTried then
        return kernel32 ~= nil
    end

    ffiTried = true

    local ok, library = pcall(require, "ffi")

    if not ok then
        return false
    end

    ok = pcall(function()
        library.cdef(CDEF)
        kernel32 = library.load("kernel32")
    end)

    if ok then
        ffi = library
    else
        kernel32 = nil
    end

    return ok
end

-- Executa o comando sem criar janela e captura a saída.
-- Retorna saída, código de saída (ou nil se não conseguiu).
local function spawnHidden(command)
    local attributes = ffi.new("docly_SECURITY_ATTRIBUTES")
    attributes.nLength = ffi.sizeof(attributes)
    attributes.lpSecurityDescriptor = nil
    attributes.bInheritHandle = 1

    local readPipe = ffi.new("void*[1]")
    local writePipe = ffi.new("void*[1]")

    if kernel32.CreatePipe(readPipe, writePipe, attributes, 0) == 0 then
        return nil
    end

    -- O processo filho não deve herdar a ponta de leitura
    kernel32.SetHandleInformation(readPipe[0], 1, 0)

    -- stdin e stderr vão para o "NUL"
    local nul = kernel32.CreateFileA(
        "NUL", 0xC0000000, 3, attributes, 3, 0, nil
    )

    local nulValid = tonumber(ffi.cast("intptr_t", nul)) ~= -1

    local startup = ffi.new("docly_STARTUPINFOA")
    startup.cb = ffi.sizeof(startup)
    startup.dwFlags = 0x100 -- STARTF_USESTDHANDLES
    startup.hStdInput = nulValid and nul or nil
    startup.hStdOutput = writePipe[0]
    startup.hStdError = nulValid and nul or nil

    local info = ffi.new("docly_PROCESS_INFORMATION")
    local line = ffi.new("char[?]", #command + 1, command)

    -- 0x08000000 = CREATE_NO_WINDOW
    local created = kernel32.CreateProcessA(
        nil, line, nil, nil, 1, 0x08000000, nil, nil, startup, info
    )

    -- Fecha as cópias do pai: sem isso a leitura nunca chega ao fim
    kernel32.CloseHandle(writePipe[0])

    if nulValid then
        kernel32.CloseHandle(nul)
    end

    if created == 0 then
        kernel32.CloseHandle(readPipe[0])
        return nil
    end

    local chunks = {}
    local buffer = ffi.new("char[65536]")
    local count = ffi.new("uint32_t[1]")

    while kernel32.ReadFile(readPipe[0], buffer, 65536, count, nil) ~= 0
    and count[0] > 0 do
        chunks[#chunks + 1] = ffi.string(buffer, count[0])
    end

    kernel32.WaitForSingleObject(info.hProcess, 5000)

    local code = ffi.new("uint32_t[1]")
    kernel32.GetExitCodeProcess(info.hProcess, code)

    kernel32.CloseHandle(info.hProcess)
    kernel32.CloseHandle(info.hThread)
    kernel32.CloseHandle(readPipe[0])

    return table.concat(chunks), tonumber(code[0])
end

local function runHidden(command)
    if not initFfi() then
        return nil
    end

    local ok, output, code = pcall(spawnHidden, command)

    if ok and output ~= nil then
        return output, code
    end

    return nil
end

-- Plano B: io.popen (abre uma janela de terminal por um instante)
local function run(command)
    local ok, handle = pcall(io.popen, command, "r")

    if not ok or not handle then
        return nil
    end

    local output = handle:read("*a")
    handle:close()

    return output
end

local function nameOf(path)
    return path:match("([^/\\]+)$") or path
end

local function escapePowerShellLiteral(value)
    return "'" .. value:gsub("'", "''") .. "'"
end

local function buildSaveCommand(kind, defaultName)
    local isDocly = kind == "docly"
    local filter = isDocly
        and "Arquivo Docly|*.docly"
        or "Arquivo de texto|*.txt"
    local title = isDocly and "Exportar arquivo Docly" or "Exportar arquivo de texto"

    local script = table.concat({
        "Add-Type -AssemblyName System.Windows.Forms",
        "$ErrorActionPreference = 'Stop'",
        "try {",
        "  $owner = New-Object System.Windows.Forms.Form",
        "  $owner.TopMost = $true",
        "  $dialog = New-Object System.Windows.Forms.SaveFileDialog",
        "  $dialog.Title = " .. escapePowerShellLiteral(title),
        "  $dialog.Filter = " .. escapePowerShellLiteral(filter),
        "  $dialog.FileName = " .. escapePowerShellLiteral(defaultName .. (isDocly and ".docly" or ".txt")),
        "  $dialog.AddExtension = $true",
        "  $dialog.DefaultExt = " .. escapePowerShellLiteral(isDocly and "docly" or "txt"),
        "  if ($dialog.ShowDialog($owner) -eq 'OK') {",
        "    Write-Output ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($dialog.FileName)))",
        "  }",
        "} catch { exit 2 }"
    }, "\n")

    local encoded = love.data.encode("string", "base64", toUtf16LE(script))

    return "powershell -NoProfile -STA -ExecutionPolicy Bypass "
        .. "-EncodedCommand " .. encoded
end

local function decodeBase64(text)
    local ok, data = pcall(love.data.decode, "string", "base64", text or "")

    if ok then
        return data
    end

    return nil
end

-- Windows ---------------------------------------------------------------

-- O PowerShell devolve tudo em base64 (nome, tamanho e bytes), assim não
-- dependemos de codificação de console nem de caminhos com acento no Lua
local function buildWindowsCommand(kind)
    local isImage = kind == "image"
    local filter = isImage
        and "Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.tga"
        or (kind == "docly" and "Arquivo Docly|*.docly|Todos os arquivos|*.*"
            or "Todos os arquivos|*.*")

    local lines = {
        "Add-Type -AssemblyName System.Windows.Forms",
        "$ErrorActionPreference = 'Stop'",
        "try {",
        "  $owner = New-Object System.Windows.Forms.Form",
        "  $owner.TopMost = $true",
        "  $dialog = New-Object System.Windows.Forms.OpenFileDialog",
        "  $dialog.Title = '" .. (isImage and "Escolher imagem" or "Escolher arquivo") .. "'",
        "  $dialog.Filter = '" .. filter .. "'",
        "  if ($dialog.ShowDialog($owner) -eq 'OK') {",
        "    $name = $dialog.FileName",
        "    Write-Output ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($name)))",
        "    Write-Output (Get-Item -LiteralPath $name).Length"
    }

    if isImage then
        lines[#lines + 1] =
            "    Write-Output ([Convert]::ToBase64String("
            .. "[System.IO.File]::ReadAllBytes($name)))"
    end

    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "} catch { exit 2 }"

    local script = table.concat(lines, "\n")

    -- -EncodedCommand evita problemas de aspas (UTF-16LE em base64)
    local encoded = love.data.encode("string", "base64", toUtf16LE(script))

    return "powershell -NoProfile -STA -ExecutionPolicy Bypass "
        .. "-EncodedCommand " .. encoded
end

local function parseWindowsOutput(output, isImage)
    local parts = {}

    for line in output:gmatch("[^\r\n]+") do
        parts[#parts + 1] = line
    end

    if #parts == 0 then
        return nil, "cancelled"
    end

    local path = decodeBase64(parts[1])

    if not path or path == "" then
        return nil, "cancelled"
    end

    local result = {
        path = path,
        name = nameOf(path),
        size = tonumber(parts[2])
    }

    if isImage then
        local data = decodeBase64(parts[3])

        if not data or #data == 0 then
            return nil, "unavailable"
        end

        result.data = data
    end

    return result
end

local function windowsPick(kind)
    local command = buildWindowsCommand(kind)

    -- 1) sem janela de terminal
    local output, code = runHidden(command)

    -- 2) plano B, caso o método acima não funcione
    if output == nil or code ~= 0 then
        output = run(command .. " 2>nul")
    end

    if output == nil then
        return nil, "unavailable"
    end

    return parseWindowsOutput(output, kind == "image")
end

local function parseSaveOutput(output)
    local path = output:match("^%s*(.-)%s*$")

    if path == "" then
        return nil, "cancelled"
    end

    path = decodeBase64(path)

    if not path or path == "" then
        return nil, "cancelled"
    end

    return path
end

local function windowsSave(kind, defaultName)
    local command = buildSaveCommand(kind, defaultName)
    local output, code = runHidden(command)

    if output == nil or code ~= 0 then
        output = run(command .. " 2>nul")
    end

    if output == nil then
        return nil, "unavailable"
    end

    return parseSaveOutput(output)
end

-- macOS / Linux ---------------------------------------------------------

local function unixPick(kind, command)
    local output = run(command)

    if output == nil then
        return nil, "unavailable"
    end

    local path = output:match("^%s*(.-)%s*$")

    if path == "" then
        return nil, "cancelled"
    end

    local handle = io.open(path, "rb")

    if not handle then
        return nil, "unavailable"
    end

    local result = { path = path, name = nameOf(path) }

    result.size = handle:seek("end")
    handle:seek("set", 0)

    if kind == "image" then
        result.data = handle:read("*a")
    end

    handle:close()

    return result
end

function FileDialog.pick(kind)
    local system = love.system.getOS()

    if system == "Windows" then
        return windowsPick(kind)
    elseif system == "OS X" then
        local types = kind == "image"
            and ' of type {"png","jpg","jpeg","bmp","tga"}'
            or ""

        return unixPick(
            kind,
            "osascript -e 'POSIX path of (choose file" .. types .. ")' 2>/dev/null"
        )
    end

    local filter = kind == "image"
        and " --file-filter='Imagens | *.png *.jpg *.jpeg *.bmp *.tga'"
        or ""

    return unixPick(
        kind,
        "zenity --file-selection" .. filter .. " 2>/dev/null"
            .. " || kdialog --getopenfilename 2>/dev/null"
    )
end

function FileDialog.save(kind, defaultName)
    local system = love.system.getOS()

    if system == "Windows" then
        return windowsSave(kind, defaultName)
    end

    local extension = kind == "docly" and "docly" or "txt"
    local title = kind == "docly"
        and "Exportar arquivo Docly"
        or "Exportar arquivo de texto"

    if system == "OS X" then
        local script = "set theName to choose file name "
            .. "with prompt " .. string.format("%q", title)
            .. " default name " .. string.format("%q", defaultName .. "." .. extension)

        local output = run("osascript -e '" .. script:gsub("'", "'\"'\"'") .. "' 2>/dev/null")

        if not output then
            return nil, "unavailable"
        end

        local path = output:match("^%s*(.-)%s*$")

        return path ~= "" and path or nil, path ~= "" and nil or "cancelled"
    end

    local output = run(
        "zenity --file-selection --save --confirm-overwrite "
        .. "--title='" .. title .. "' "
        .. "--filename='" .. defaultName .. "." .. extension .. "' "
        .. "2>/dev/null || kdialog --getsavefilename "
        .. "'" .. defaultName .. "." .. extension .. "' "
        .. "'*." .. extension .. "' 2>/dev/null"
    )

    if output == nil then
        return nil, "unavailable"
    end

    local path = output:match("^%s*(.-)%s*$")

    if path == "" then
        return nil, "cancelled"
    end

    return path
end

-- Só para testes
FileDialog._parseWindowsOutput = parseWindowsOutput
FileDialog._buildWindowsCommand = buildWindowsCommand

return FileDialog