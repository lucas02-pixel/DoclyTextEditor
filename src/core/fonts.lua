local Fonts = {}

-- O LÖVE diferencia maiúsculas de minúsculas no caminho
local FONT_PATH = "assets/fonts/Font.ttf"

local warned = false
local cache = {}

local function make(size)
    if love.filesystem.getInfo(FONT_PATH) then
        local ok, font = pcall(love.graphics.newFont, FONT_PATH, size)

        if ok then
            return font
        end

        if not warned then
            print("Docly: não foi possível carregar " .. FONT_PATH
                .. " (" .. tostring(font) .. "). Usando a fonte padrão.")
            warned = true
        end
    end

    return love.graphics.newFont(size)
end

-- Fonte em qualquer tamanho (com cache)
function Fonts.sized(size)
    local font = cache[size]

    if not font then
        font = make(size)
        cache[size] = font
    end

    return font
end

function Fonts.load()
    Fonts.small = Fonts.sized(14)
    Fonts.ui = Fonts.sized(18)
    Fonts.title = Fonts.sized(28)
end

return Fonts