local Homepage = require("src.interface.homepage")
local Sidebar = require("src.interface.sidebar")
local Editor = require("src.editor.editor")
local Fonts = require("src.core.fonts")
local Documents = require("src.editor.document_manager")

local App = {}

local currentDocument = nil
local saveTimer = 0

-- Cursor do mouse ------------------------------------------------------

local cursors = {}
local currentCursor = nil

-- Cursor da borracha: um círculo do tamanho real da borracha
local function makeEraserCursor(radius)
    local size = radius * 2 + 6
    local center = size / 2

    local data = love.image.newImageData(size, size)

    data:mapPixel(function(x, y)
        local dx = x + 0.5 - center
        local dy = y + 0.5 - center
        local distance = math.sqrt(dx * dx + dy * dy)
        local ring = math.abs(distance - radius)

        if ring < 1 then
            return 0.1, 0.1, 0.1, 1
        elseif ring < 2 then
            return 1, 1, 1, 0.85
        end

        return 0, 0, 0, 0
    end)

    return love.mouse.newCursor(data, center, center)
end

local function setCursor(kind)
    if kind == currentCursor then
        return
    end

    local cursor = cursors[kind]

    if not cursor then
        local radius = kind:match("^eraser:(%d+)$")

        if radius then
            local ok, made = pcall(makeEraserCursor, tonumber(radius))

            cursor = ok and made or love.mouse.getSystemCursor("crosshair")
        else
            cursor = love.mouse.getSystemCursor(kind)
        end

        cursors[kind] = cursor
    end

    love.mouse.setCursor(cursor)

    currentCursor = kind
end

local function updateCursor(x, y)
    local kind = "arrow"

    if currentDocument then
        if Editor.hitBack(x, y) or Sidebar.hit(x, y) then
            kind = "hand"
        else
            kind = Editor.cursorAt(x, y, Sidebar.activeTool, currentDocument)
        end
    elseif Homepage.isClickable(x, y) then
        kind = "hand"
    end

    setCursor(kind)
end

local function closeDocument()
    currentDocument = nil
    Sidebar.activeTool = nil
    Editor.reset()
end

-- Algumas ferramentas voltam ao modo normal depois de criar algo
local function applyToolReset()
    if Editor.takeToolReset() then
        Sidebar.activeTool = nil
    end
end

-- Callbacks ------------------------------------------------------------

function App.load()
    Fonts.load()
    Editor.load()
    Documents.loadAppData()
    love.graphics.setBackgroundColor(1, 1, 1)
end

function App.quit()
    local ok, err = Documents.saveAppData()

    if not ok then
        print("Docly: falha ao salvar os documentos ao sair (" .. tostring(err) .. ")")
    end

    return false
end

function App.update(dt)
    if currentDocument then
        Editor.update(dt)
    end

    saveTimer = saveTimer + dt

    if saveTimer >= 0.5 then
        saveTimer = 0
        Documents.saveAppData()
    end
end

function App.draw()
    if currentDocument then
        Editor.draw(currentDocument, Sidebar.activeTool)
        Sidebar.draw()
    else
        Homepage.draw()
    end
end

function App.mousepressed(x, y, button)
    if currentDocument then
        if button == 1 and Editor.hitBack(x, y) then
            closeDocument()
        else
            local before = Sidebar.activeTool

            if Sidebar.mousepressed(x, y, button) then
                local tool = Sidebar.activeTool

                -- Imagem e anexo abrem o seletor de arquivos na hora
                if tool ~= before
                and (tool == "image" or tool == "attachment") then
                    Editor.pickFile(currentDocument, tool)
                    applyToolReset()
                end
            else
                Editor.mousepressed(
                    x,
                    y,
                    button,
                    currentDocument,
                    Sidebar.activeTool
                )

                applyToolReset()
            end
        end
    else
        currentDocument = Homepage.mousepressed(x, y, button)
    end

    updateCursor(x, y)
end

function App.mousemoved(x, y, dx, dy)
    if currentDocument then
        Editor.mousemoved(x, y, dx, dy, currentDocument)
    else
        Homepage.mousemoved(x, y)
    end

    updateCursor(x, y)
end

function App.mousereleased(x, y, button)
    if currentDocument then
        Editor.mousereleased(x, y, button, currentDocument)
        applyToolReset()
    end

    updateCursor(x, y)
end

function App.textinput(text)
    if currentDocument then
        Editor.textinput(text, currentDocument, Sidebar.activeTool)
    else
        Homepage.textinput(text)
    end
end

function App.keypressed(key)
    if currentDocument then
        if key == "escape" then
            if Editor.escape(currentDocument) then
                return
            end

            closeDocument()
            updateCursor(love.mouse.getPosition())
            return
        end

        Editor.keypressed(key, currentDocument, Sidebar.activeTool)
    else
        local document = Homepage.keypressed(key)

        if document then
            currentDocument = document
            updateCursor(love.mouse.getPosition())
        end
    end
end

function App.filedropped(file)
    if currentDocument then
        Editor.filedropped(file, currentDocument, Sidebar.activeTool)
        applyToolReset()
    end
end

function App.isAnimating()
    return currentDocument
        and Editor.isAnimating()
        or false
end

function App.wheelmoved(x, y)
    if not currentDocument then
        Homepage.wheelmoved(x, y)
    end
end

-- Pede redesenho em movimentos do mouse (desenhando ou selecionando)
function App.wantsMouseMove()
    if currentDocument then
        return Editor.wantsMouseMove()
    end

    return true
end

return App