local App = require("src.core.app")

local needsRedraw = true

local function handleEvent(name, ...)
    if name == "quit" then
        if love.quit and love.quit() then
            return false
        end

        return true
    end

    local handler = love.handlers[name]

    if handler then
        handler(...)
    end

    return false
end

-- Mover o mouse só exige redesenho quando há um traço em andamento
local function requiresRedraw(name)
    if name == "mousemoved" then
        return App.wantsMouseMove()
    end

    return true
end

function love.load()
    App.load()
end

function love.quit()
    return App.quit()
end

function love.update(dt)
    App.update(dt)
end

function love.draw()
    App.draw()
end

function love.mousepressed(x, y, button)
    App.mousepressed(x, y, button)
end

function love.mousemoved(x, y, dx, dy, istouch)
    App.mousemoved(x, y, dx, dy)
end

function love.mousereleased(x, y, button)
    App.mousereleased(x, y, button)
end

function love.textinput(text)
    App.textinput(text)
end

function love.keypressed(key)
    App.keypressed(key)
end

function love.filedropped(file)
    App.filedropped(file)
end

function love.run()
    if love.load then
        love.load(
            love.arg.parseGameArguments(arg),
            arg
        )
    end

    if love.timer then
        love.timer.step()
    end

    return function()
        love.event.pump()

        for name, a, b, c, d, e, f in love.event.poll() do
            if handleEvent(name, a, b, c, d, e, f) then
                return 0
            end

            if requiresRedraw(name) then
                needsRedraw = true
            end
        end

        local animating = App.isAnimating()

        if (needsRedraw or animating) and love.graphics.isActive() then
            -- Limita o dt: depois de ficar ocioso em event.wait()
            -- o primeiro dt seria enorme e a animação "pularia"
            local dt = math.min(love.timer.step(), 1 / 30)

            love.update(dt)

            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())

            love.draw()

            love.graphics.present()

            needsRedraw = false
        end

        if App.isAnimating() then
            love.timer.sleep(1 / 60)
        else
            local name, a, b, c, d, e, f = love.event.wait()

            if name then
                if handleEvent(name, a, b, c, d, e, f) then
                    return 0
                end

                if requiresRedraw(name) then
                    needsRedraw = true
                end
            end
        end
    end
end