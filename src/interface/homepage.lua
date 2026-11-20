local Documents = require("src.editor.document_manager")
local Fonts = require("src.core.fonts")
local FileDialog = require("src.core.file_dialog")

local Homepage = {}

function Homepage.draw()
    local width = love.graphics.getWidth()

    love.graphics.clear(1, 1, 1)

    -- Logo
    love.graphics.setFont(Fonts.title)
    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.print("Docly", 55, 36)

    love.graphics.setFont(Fonts.ui)

    -- Pesquisa (ainda visual)
    love.graphics.setColor(0.96, 0.96, 0.96)
    love.graphics.rectangle(
        "fill", width - 390, 30, 330, 42, 10, 10
    )

    love.graphics.setColor(0.45, 0.45, 0.45)
    love.graphics.print(
        "Pesquisar documentos...", width - 375, 41
    )

    -- Título
    love.graphics.setFont(Fonts.title)
    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.print("Seus documentos", 55, 120)

    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(0.45, 0.45, 0.45)
    love.graphics.print(
        "Tudo o que você cria, em um só lugar.",
        55, 162
    )

    -- Botão novo documento
    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.rectangle(
        "fill", 55, 220, 190, 48, 10, 10
    )

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("+ Novo documento", 71, 233)

    -- Abrir arquivo Docly
    love.graphics.setColor(0.96, 0.96, 0.96)
    love.graphics.rectangle(
        "fill", 260, 220, 190, 48, 10, 10
    )

    love.graphics.setColor(0.08, 0.08, 0.08)
    love.graphics.print("Abrir .docly", 286, 233)

    -- Recentes
    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.print("Recentes", 55, 325)

    local documents = Documents.getAll()

    if #documents == 0 then
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print(
            "Seus documentos aparecerão aqui.",
            55, 375
        )
    end

    for i, document in ipairs(documents) do
        local x = 55 + ((i - 1) % 4) * 250
        local y = 370 + math.floor((i - 1) / 4) * 165

        love.graphics.setColor(0.97, 0.97, 0.97)
        love.graphics.rectangle(
            "fill", x, y, 220, 145, 12, 12
        )

        love.graphics.setColor(0.08, 0.08, 0.08)
        love.graphics.print(document.title, x + 15, y + 20)

        love.graphics.setFont(Fonts.small)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print(
            "Documento Docly", x + 15, y + 55
        )
        love.graphics.setFont(Fonts.ui)
    end

    -- Pastas
    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.print("Pastas", 55, 570)

    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.print("+ Criar pasta", 55, 610)
end

function Homepage.mousepressed(x, y, button)
    if button ~= 1 then
        return nil
    end

    -- Criar documento
    if x >= 55 and x <= 245
    and y >= 220 and y <= 268 then
        return Documents.create()
    end

    -- Abrir arquivo .docly
    if x >= 260 and x <= 450
    and y >= 220 and y <= 268 then
        local result, reason = FileDialog.pick("docly")

        if result then
            local document, openReason = Documents.openDocly(result.path)

            if document then
                return document
            end

            print("Docly: não foi possível abrir o arquivo (" .. tostring(openReason) .. ")")
        elseif reason ~= "cancelled" then
            print("Docly: não foi possível abrir o seletor")
        end

        return nil
    end

    -- Abrir documento existente
    local documents = Documents.getAll()

    for i, document in ipairs(documents) do
        local cardX = 55 + ((i - 1) % 4) * 250
        local cardY = 370 + math.floor((i - 1) / 4) * 165

        if x >= cardX and x <= cardX + 220
        and y >= cardY and y <= cardY + 145 then
            return document
        end
    end

    return nil
end

-- true se o mouse está sobre algo clicável (botão ou card)
function Homepage.isClickable(x, y)
    if x >= 55 and x <= 245 and y >= 220 and y <= 268 then
        return true
    end

    if x >= 260 and x <= 450 and y >= 220 and y <= 268 then
        return true
    end

    for i = 1, #Documents.getAll() do
        local cardX = 55 + ((i - 1) % 4) * 250
        local cardY = 370 + math.floor((i - 1) / 4) * 165

        if x >= cardX and x <= cardX + 220
        and y >= cardY and y <= cardY + 145 then
            return true
        end
    end

    return false
end

return Homepage