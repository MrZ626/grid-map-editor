local ins=table.insert

---@alias GridMap Mat<false|Cell>

---@type Zenitha.Scene
local scene={}

local histDat ---@type string.buffer[]
local histPtr ---@type integer histDat[histPtr] should be nil on latest state

---@class Cell
---@field type integer 1B [0, 255], 128+ means has data
---@field style integer 1B [0, 255]
---@field data? integer 2B [0, 65535]

---@class Selection
---@field x integer?
---@field y integer?
---@field x1 integer? -- x1, guaranteed smaller than x2
---@field y1 integer? -- y1, guaranteed smaller than y2
---@field x2 integer? -- x2, guaranteed greater than x1
---@field y2 integer? -- y2, guaranteed greater than y1

local keybind={} ---@type table<string, integer>

local map ---@type GridMap
local cam=GC.newCamera() ---@type Zenitha.Camera
local clipboard ---@type string.buffer
local sel ---@type Selection
local mouse={x=0,y=0}
local penInputBuffer ---@type string?
-- local penInputMode ---@type false|'id'|'data'
local pen={
    type=1,
    style=0,
}

---@param m GridMap
---@param x1? integer
---@param y1? integer
---@param x2? integer
---@param y2? integer
local function dumpMap(m,x1,y1,x2,y2)
    if not x1 then x1,y1,x2,y2=1,1,#m[1],#m end
    local buf=STRING.newBuf()
    local w=x2-x1+1
    buf:put(string.char(w%256),string.char(math.floor(w/256)))
    for y=y1,y2 do
        for x=x1,x2 do
            ---@type Cell
            local c=m[y][x]
            if not c then
                buf:put('\0\0')
            elseif not c.data then
                buf:put(string.char(c.type),string.char(c.style))
            else
                buf:put(
                    string.char(c.type+128),
                    string.char(c.style),
                    string.char(c.data%256),
                    string.char(math.floor(c.data/256))
                )
            end
        end
    end
    return buf
end

---@param buf string.buffer
---@return GridMap
local function loadMap(buf)
    local d=STRING.newBuf():set(buf:ref())
    local width=d:get(1):byte()+d:get(1):byte()*256
    local m={}
    while true do
        local l={}
        for x=1,width do
            local c
            local t=d:get(2)
            if t=='\0\0' then
                c=false
            elseif t:byte(1)<128 then
                c={type=t:byte(1),style=t:byte(2)}
            else
                c={type=t:byte(1)-128,style=t:byte(2),data=d:get(1):byte()+d:get(1):byte()*256}
            end
            l[x]=c
        end
        ins(m,l)
        if #d==0 then break end
    end
    return m
end

local function init(mapData)
    if mapData then
        map=loadMap(mapData)
    else
        map=TABLE.newMat(false,3,3)
    end
    cam.k0=26
    cam.x0=-cam.k0*#map[1]/2
    cam.y0=-cam.k0*#map/2
    penInputBuffer=nil
    sel={
        x=nil,
        y=nil,
        x1=nil,
        y1=nil,
        x2=nil,
        y2=nil,
    }
    histDat={}
    histPtr=1
end

local function pushHist()
    if histDat[histPtr] then
        -- Remove redo history
        for i=#histDat,histPtr,-1 do
            histDat[i]=nil
        end
    end
    ins(histDat,dumpMap(map))
    histPtr=#histDat+1
end

local function loadConfig()
    if FILE.exist('keybind.lua') then keybind=FILE.load('keybind.lua','-luaon') end
end
function scene.load()
    FILE.createDirectory({'saves','texture'})
    if not FILE.exist('keybind.lua') then FILE.save('return{\n    w=1,\n}','keybind.lua') end
    loadConfig()
    init()
end

function scene.mouseMove(x,y,dx,dy)
    if love.mouse.isDown(3) then
        cam:move(dx,dy)
    else
        local mx,my=SCR.xOy:transformPoint(x,y)
        mx,my=SCR.xOy_m:inverseTransformPoint(mx,my)
        mx,my=cam.transform:inverseTransformPoint(mx,my)
        mouse.x=math.ceil(mx)
        mouse.y=math.ceil(my)
    end
end
function scene.mouseDown(x,y,k)
    if love.keyboard.isDown('lctrl','rctrl') then
        if k==1 then
            if not sel.x then
                sel.x,sel.y=mouse.x,mouse.y
            else
                sel.x1,sel.y1=math.min(sel.x,mouse.x),math.min(sel.y,mouse.y)
                sel.x2,sel.y2=math.max(sel.x,mouse.x),math.max(sel.y,mouse.y)
            end
        end
    else
        if k==1 then
            if mouse.y<1 then
                local cnt=1-mouse.y
                for _=1,cnt do ins(map,1,TABLE.new(false,#map[1])) end
                cam.y0=cam.y0-cam.k*cnt
                cam.y=cam.y0
                mouse.y=1
            elseif mouse.y>#map then
                for _y=#map+1,mouse.y do map[_y]=TABLE.new(false,#map[1]) end
            end
            if mouse.x<1 then
                local cnt=1-mouse.x
                for _y=1,#map do
                    for _=1,cnt do ins(map[_y],1,false) end
                end
                cam.x0=cam.x0-cam.k*cnt
                cam.x=cam.x0
                mouse.x=1
            elseif mouse.x>#map[1] then
                for _y=1,#map do
                    for _x=#map[1]+1,mouse.x do
                        map[_y][_x]=false
                    end
                end
            end
            map[mouse.y][mouse.x]=TABLE.copyAll(pen)
        elseif k==2 then
            if MATH.between(mouse.y,1,#map) and MATH.between(mouse.x,1,#map[1]) then
                map[mouse.y][mouse.x]=false
            end
        end
    end
end
function scene.wheelMove(_,dy)
    cam:scale(1.26^dy)
end

function scene.keyDown(key,isRep)
    if isRep then return end
    if love.keyboard.isDown('lctrl','rctrl') then
        if key=='s' then
            FILE.save(dumpMap(map):tostring(),os.date("saves/map_%y%m%d_%H%M%S"))
            MSG('check',"Saved!")
        elseif key=='c' then
            if sel.x1 then
                clipboard=dumpMap(map,sel.x1,sel.y1,sel.x2,sel.y2)
                MSG('check',"Copied!")
            end
        elseif key=='v' then
            if sel.x then
                local m=loadMap(clipboard)
                local px1,py1=sel.x1 or sel.x,sel.y1 or sel.y
                for y=1,math.min(#m,sel.y1 and sel.y2-sel.y1+1 or 1e99) do
                    for x=1,math.min(#m[1],sel.x1 and sel.x2-sel.x1+1 or 1e99) do
                        if MATH.between(py1+y-1,1,#map) and MATH.between(px1+x-1,1,#map[1]) then
                            map[py1+y-1][px1+x-1]=m[y][x]
                        end
                    end
                end
                -- pushHist()
                MSG('check',"Pasted!")
            end
        elseif key=='o' then
            UTIL.openSaveDirectory()
        elseif key=='l' then
            loadConfig()
        end
    else
        if penInputBuffer and tonumber(key) then
            penInputBuffer=penInputBuffer..key
        elseif type(keybind[key])=='number' then
            pen.type=keybind[key]
            pen.style=0
            penInputBuffer=""
        elseif key=='space' or key=='return' then
            if penInputBuffer then
                pen.style=tonumber(penInputBuffer) or 0
                penInputBuffer=nil
            else
                penInputBuffer=""
            end
        elseif key=='backspace' then
            if penInputBuffer then
                penInputBuffer=penInputBuffer:sub(1,-2)
            end
        elseif key=='z' then
            -- Undo
            if histPtr>1 then
                histPtr=histPtr-1
                loadMap(histDat[histPtr])
            end
        elseif key=='y' then
            -- Redo
            if histDat[histPtr] then
                loadMap(histDat[histPtr])
                histPtr=histPtr+1
            end
        elseif key=='delete' then
            if sel.x1 then
                for y=sel.y1,sel.y2 do
                    for x=sel.x1,sel.x2 do
                        map[y+1][x+1]=false
                    end
                end
                -- pushHist()
            end
        elseif key=='escape' then
            TABLE.clear(sel)
        end
    end
    return true
end

function scene.fileDrop(f)
    init(FILE.read(f))
end

function scene.update(dt)
    cam:update(dt)
end

function scene.draw()
    GC.replaceTransform(SCR.xOy_m)
    cam:apply()
    local w,h=#map[1],#map
    GC.setLineWidth(.04)
    GC.setColor(1,1,1)
    GC.rectangle('line',-.02,-.02,w+.04,h+.04)
    GC.setLineWidth(.02)
    FONT.set(20)
    for y=1,h do
        for x=1,w do
            local c=map[y][x]
            if c then
                GC.rectangle('line',x-1+.05,y-1+.05,.9,.9)
                GC.print(c.type,x-1+.1,y-1+.05,nil,.01)
                GC.print(c.style,x-1+.1,y-1+.35,nil,.01)
                if c.data then GC.print(c.data,x-1+.1,y-1+.65,nil,.01) end
            end
        end
    end
    if sel.x then
        GC.setColor(0,1,1)
        -- Starting point set
        GC.circle('line',sel.x-1+.5,sel.y-1+.5,.26)
        if sel.x1 then
            -- Both corner set
            GC.rectangle('line',sel.x1-1+.2,sel.y1-1+.2,sel.x2-sel.x1+.6,sel.y2-sel.y1+.6)
        end
    end
    GC.setColor(1,0,1)
    GC.rectangle('line',mouse.x-1,mouse.y-1,1,1,.26)

    GC.replaceTransform(SCR.xOy_ul)
    GC.setColor(1,1,1)
    FONT.set(40)
    GC.print("Type:"..pen.type,10,0)
    if penInputBuffer then
        GC.print("Style: "..penInputBuffer.."...",10,40)
    else
        GC.print("Style: "..pen.style,10,40)
    end
end

return scene
