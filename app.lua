#!/usr/bin/env luajit

do -- try to load a config file if it exists
    local ok, res = pcall(function()
        local file = debug.getinfo(1, 'S').short_src:gsub('([\\/])[^\\/]*$', '%1')..'config.lua'
        assert(loadfile(file))()
    end)
    if not ok then print(res) end
end

local lgi = require 'lgi'
local LuaOpenFing = lgi.package 'LuaOpenFing' -- package for custom widgets
local GLib = lgi.require 'GLib'
local Gtk = lgi.require 'Gtk'
local GObject = lgi.require 'GObject'
local Soup = lgi.require 'Soup'
local Gst = lgi.require 'Gst'
local GstVideo = lgi.require 'GstVideo'
local json = require 'json'
local unpack = unpack or table.unpack

-------------------------------------------------------------------------------

local Dao = {}
Dao.__index = Dao

function Dao:new(params)
    local file = params.file
        or (os.getenv 'HOME' and os.getenv 'HOME':gsub('/*$', '') .. '/.lua-openfing.json')
    local objs = {}
    local fd = io.open(file)
    if fd then
        objs = json.decode(fd:read '*all')
        fd:close()
    end
    return setmetatable({objs=objs, file=file}, self)
end

function Dao:save(id, object)
    self.objs[id] = object
    local fd = assert(io.open(self.file, 'w'))
    fd:write(json.encode(self.objs))
    fd:close()
end

function Dao:load(id)
    return self.objs[id]
end

local dao = Dao:new{}

-- Objects in dao:
-- courses = list of {code:string, eva=url:string, name=description:string}

-------------------------------------------------------------------------------

local function versionCompare(a, b) -- similar to the '<' string operator
    local ai, bi = 1, 1
    while true do
        local as, bs = a:match('^[^%d]*', ai), b:match('^[^%d]*', bi)
        if as ~= bs then return as < bs end
        ai, bi = ai + #as, bi + #bs
        as, bs = a:match('^%d*', ai), b:match('^%d*', bi)
        if as == '' or bs == '' then return bs ~= '' end
        local an, bn = tonumber(as), tonumber(bs)
        if an ~= bn then return an < bn end
        ai, bi = ai + #as, bi + #bs
    end
end

local function guiPlayer(app, course, classesList, i, choose)
    local closed = false
    local old = {}
    local vbox = Gtk.Box {orientation = 'VERTICAL', margin = 10, spacing = 10}
    local video = Gtk.DrawingArea {expand = true}
    local controls = Gtk.Box {orientation = 'HORIZONTAL'}
    local currentFormat, ignoreNextStreamError = 'MP4', false
    local back = Gtk.Button {
        label = 'Atrás',
        image = Gtk.Image { stock = Gtk.STOCK_GO_BACK, icon_size = Gtk.IconSize.BUTTON },
        margin_right = 10
    }
    local playPause = Gtk.Button {
        image = Gtk.Image { stock = Gtk.STOCK_MEDIA_PLAY, icon_size = Gtk.IconSize.BUTTON },
    }
    local stop = Gtk.Button {
        image = Gtk.Image { stock = Gtk.STOCK_MEDIA_STOP, icon_size = Gtk.IconSize.BUTTON },
    }
    local time = Gtk.Label {
        margin_left = 5
    }
    local slider = Gtk.Scale {
        orientation = 'HORIZONTAL', draw_value = false,
        adjustment = Gtk.Adjustment{value=0, lower=0, upper=100, step_increment=1, page_increment=10},
        hexpand = true, margin_left = 5, margin_right = 5
    }
    local speed
    local menub = Gtk.MenuButton {
        direction = 'UP', halign = 'END',
        popup = Gtk.Menu {
            Gtk.MenuItem { label = 'Velocidad', visible = true, submenu = Gtk.Menu {
                Gtk.MenuItem { label = '0.5x', visible = true, on_activate = function()speed(0.5)end },
                Gtk.MenuItem { label = '0.75x', visible = true, on_activate = function()speed(0.75)end },
                Gtk.MenuItem { label = 'Normal', visible = true, on_activate = function()speed(1)end },
                Gtk.MenuItem { label = '1.25x', visible = true, on_activate = function()speed(1.25)end },
                Gtk.MenuItem { label = '1.5x', visible = true, on_activate = function()speed(1.5)end },
                Gtk.MenuItem { label = '2x', visible = true, on_activate = function()speed(2)end },
            }}
        }
    }
    local menu = Gtk.Menu {
    }
    local playbin = Gst.ElementFactory.make('playbin', 'playbin')
    vbox:add(video)
    vbox:add(controls)
    controls:add(back)
    controls:add(playPause)
    controls:add(stop)
    controls:add(time)
    controls:add(slider)
    controls:add(menub)
    function vbox:on_realize()
        app:title(('OpenFING - %s: %s (%s)'):format(course.id, classesList[i].id, classesList[i].description))
    end
    function video:on_realize()
        local id
        id = lgi.require 'GdkX11'.X11Window.get_xid(self:get_window())
        GstVideo.VideoOverlay.set_window_handle(playbin, id)
        playbin:set_state 'PLAYING'
    end
    function video:on_draw(cr)
        if not ({PLAYING=1, PAUSED=1})[playbin.current_state] then
            -- draw a black rectangle to avoid garbage
            local rec = self:get_allocation()
            cr:set_source_rgb(0, 0, 0)
            cr:rectangle(0, 0, rec.width, rec.height)
            cr:fill()
        end
        return false
    end
    function back:on_clicked()
        if closed then return end
        closed = true
        playbin:set_state 'NULL'
        return app:pop()
    end
    function playPause:on_clicked()
        local state = playbin.pending_state == 'VOID_PENDING' and playbin.current_state or playbin.pending_state
        playbin:set_state(state == 'PLAYING' and 'PAUSED' or 'PLAYING')
    end
    function stop:on_clicked()
        playbin:set_state 'NULL'
        playPause.image = Gtk.Image { stock = Gtk.STOCK_MEDIA_PLAY, icon_size = Gtk.IconSize.BUTTON }
        video:queue_draw()
    end
    function slider:on_value_changed()
        local value = slider:get_value()
        local oldValue = old.position and old.position / Gst.SECOND or 0
        if math.abs(value - oldValue) > 1 then
            playbin:seek_simple('TIME', Gst.SeekFlags.FLUSH + Gst.SeekFlags.KEY_UNIT, value * Gst.SECOND)
            time.label = ('%d:%02d'):format(math.floor(value / 60), math.floor(value) % 60)
        end
    end
    playbin:get_bus().on_message = function(bus, message)
        local t = message.type
        if t.STATE_CHANGED then
            if message.src == playbin then
                local oldState, newState, pending = message:parse_state_changed()
                playPause.image = Gtk.Image { stock = newState=='PLAYING' and Gtk.STOCK_MEDIA_PAUSE or Gtk.STOCK_MEDIA_PLAY, icon_size = Gtk.IconSize.BUTTON }
            end
        elseif t.ERROR then
            local err, deb = message:parse_error()
            if err.code == 'NOT_FOUND' and err.domain == Gst.ResourceError and currentFormat == 'MP4' then
                GLib.idle_add(GLib.PRIORITY_LOW, function()
                    playbin.uri = ('http://openfing-video.fing.edu.uy/media/%s/%s_%02d.webm'):format(
                        course.id, course.id, tonumber(classesList[i].id))
                    playbin:set_state('PLAYING')
                    currentFormat = 'WEBM'
                end)
                ignoreNextStreamError = true
                return
            elseif err.code == 'FAILED' and err.domain == Gst.StreamError and ignoreNextStreamError then
                print'ignoring'
                ignoreNextStreamError = false
                return
            end
            print(err, deb)
            Gtk.MessageDialog {
                text = ('Error code: %s (code=%s, domain=%s)\nwhile loading video\n%s'):format(
                    err.message, err.code, err.domain, deb),
                message_type = 'ERROR', buttons = 'CLOSE',
                on_response = Gtk.Widget.destroy
            }:run()
        --elseif t.BUFFERING or t.TAG then
        else
            --local types = {} for k, v in pairs(t) do table.insert(types, tostring(k)..'='..tostring(v)) end print('otra cosa?', message, table.concat(types,' '))
        end
    end
    speed = function(s)
        playbin:seek(s, 'TIME', Gst.SeekFlags.FLUSH + Gst.SeekFlags.ACCURATE,
            'SET', playbin:query_position 'TIME', 'NONE', 0)
    end
    GLib.timeout_add(GLib.PRIORITY_LOW, 100, function()
        if closed then return false end
        local duration = playbin:query_duration 'TIME'
        local position = playbin:query_position 'TIME'
        if duration ~= old.duration then
            slider:set_range(0, duration / Gst.SECOND)
            old.duration = duration
        end
        if position ~= old.position then
            old.position = position
            -- Range.set_value triggers a value-changed callback, that's why we update old.position
            -- before the signal is sent.
            local seconds = position and position / Gst.SECOND or 0
            slider:set_value(seconds)
            time.label = ('%d:%02d'):format(math.floor(seconds / 60), math.floor(seconds) % 60)
        end
        return true
    end)
    playbin.uri = ('http://openfing-video.fing.edu.uy/media/%s/%s_%02d.mp4'):format(
        course.id, course.id, tonumber(classesList[i].id))
    playbin:get_bus():add_signal_watch()
    return vbox
end

LuaOpenFing:class('ProgressCellRenderer', Gtk.CellRendererText)

function LuaOpenFing.ProgressCellRenderer:do_render(cr, widget, background_area, cell_area, flags)
    cr:new_sub_path()
    local text = self.text
    local degrees = math.pi / 180
    local x, y = cell_area.x + 1, cell_area.y + cell_area.height * .2
    local radius = cell_area.height / 3
    local width, height = radius * 2 + #self.text, math.min(cell_area.height * .6, 30)
    cr:arc(x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees)
    cr:arc(x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees)
    cr:arc(x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees)
    cr:arc(x + radius, y + radius, radius, 180 * degrees, 270 * degrees)
    cr:close_path()
    cr:stroke()
    for k,v in pairs(self.priv) do
        print('foo',k,v)
    end
    cr:set_source_rgb(1, 0, 0)
    cr:new_path()
    local from, to = text:find '1+'
    while from do
        cr:move_to(cell_area.x + 1 + radius + from - 1, cell_area.y + cell_area.height / 2)
        cr:line_to(cell_area.x + 1 + radius + to, cell_area.y + cell_area.height / 2)
        from, to = text:find('1+', to+1)
    end
    cr:stroke()
end

function LuaOpenFing.ProgressCellRenderer:do_get_preferred_width(...)
    local m = 22 + #self.text
    return m, m
end

function LuaOpenFing.ProgressCellRenderer:do_get_preferred_height_for_width(...)
    return 10, 10
end

function LuaOpenFing.ProgressCellRenderer:do_get_preferred_height(...)
    return 10, 10
end

local function guiClasses(app, course)
    local grid = Gtk.Grid {
        margin = 10
    }
    local label = Gtk.Label {
        label = 'Elija clase del curso ' .. course.description .. ':'
    }
    local classesScroll = Gtk.ScrolledWindow {
        expand = true, margin_top = 10
    }
    local classesModel = Gtk.ListStore.new {
        GObject.Type.STRING,
        GObject.Type.STRING,
        GObject.Type.STRING
    }
    local classes = Gtk.TreeView {
        expand = true,
        model = classesModel,
        Gtk.TreeViewColumn {title = "Id", sort_column_id = 0, { Gtk.CellRendererText {}, { text = 1 } }},
        Gtk.TreeViewColumn {title = "Nombre", sort_column_id = 1, { Gtk.CellRendererText {}, { markup = 2 } }},
        Gtk.TreeViewColumn {title = "Progreso", sort_column_id = 1, { LuaOpenFing.ProgressCellRenderer {}, { text = 3 } }},
    }
    local back = Gtk.Button {
        label = 'Atrás',
        image = Gtk.Image { stock = Gtk.STOCK_GO_BACK, icon_size = Gtk.IconSize.BUTTON },
        hexpand = true, halign = 'START', margin_top = 10
    }
    local eva = Gtk.Button {
        label = 'Web del curso',
        image = Gtk.Image { stock = Gtk.STOCK_INFO, icon_size = Gtk.IconSize.BUTTON },
        margin_top = 10,
        sensitive = false
    }
    local go = Gtk.Button {
        label = 'Ver video',
        image = Gtk.Image { stock = Gtk.STOCK_GO_FORWARD, icon_size = Gtk.IconSize.BUTTON },
        halign = 'END', margin_left = 10, margin_top = 10,
        sensitive = false
    }
    grid:attach(label, 0, 0, 3, 1)
    grid:attach(classesScroll, 0, 1, 3, 1)
    classesScroll:add(classes)
    grid:attach(back, 0, 2, 1, 1)
    grid:attach(eva, 1, 2, 1, 1)
    grid:attach(go, 2, 2, 1, 1)
    local info = {}
    classes:get_selection().on_changed = function()
        go.sensitive = true
    end
    function back.on_clicked()
        return app:pop()
    end
    eva.on_clicked = function()
        os.execute("xdg-open '" .. evaLink:gsub("'", "'\\''") .. "'")
    end
    local function selectClass()
        local currentClassId = classesModel[classes:get_selection():get_selected_rows()[1]][1]
        local classesList = {}
        local currentI
        for i, classId in ipairs(info.classesKeys) do
            classesList[i] = {id=classId, description=info.classes[classId]}
            if classId == currentClassId then currentI = i end
        end
        app:push(guiPlayer(app, course, classesList, currentI, function(i)
            local rowNumber
            for i, row in ipairs(classesModel) do
                if row[1] == classesList[i].id then rowNumber = i - 1 end
            end
            classes:set_cursor(Gtk.TreePath.new_from_string(tostring(rowNumber)))
        end), function() -- called on player's pop
            local idx = classes:get_selection():get_selected_rows()[1]
            classesModel[idx][3] = '' -- TODO: update progress string in model
        end)
    end
    go.on_clicked = selectClass
    function classes:on_button_press_event(event)
        if event.type == 'DOUBLE_BUTTON_PRESS' then selectClass() end
    end
    local msg = Soup.Message.new('GET', 'https://open.fing.edu.uy/data/' .. course.id .. '.json')
    local result = Soup.SessionSync {}:send_message(msg)
    function grid.on_realize()
        app:title(('OpenFING - %s (%s)'):format(course.id, course.description))
    end
    if result ~= 200 then
        Gtk.MessageDialog {
            text = 'Error code: ' .. result .. '\nwhile requesting course info',
            message_type = 'ERROR', buttons = 'CLOSE',
            on_response = Gtk.Widget.destroy
        }:run()
    else
        info = json.decode(msg.response_body.data)
        if info.eva and info.eva:match '^https?:' then
            eva.sensitive = true
        end
        info.classesKeys = {}
        for classId, _name in pairs(info.classes) do
            table.insert(info.classesKeys, classId)
        end
        table.sort(info.classesKeys, versionCompare)
        for i, classId in ipairs(info.classesKeys) do
            classesModel:append{classId, info.classes[classId], ''} -- TODO: update progress string
        end
    end
    return grid
end

local function guiCourses(app)
    local grid = Gtk.Grid {
        margin = 10
    }
    local label = Gtk.Label {
        label = 'Elija curso:'
    }
    local coursesScroll = Gtk.ScrolledWindow {
        expand = true, margin_top = 10
    }
    local coursesModel = Gtk.ListStore.new {
        GObject.Type.STRING,
        GObject.Type.STRING
    }
    local courses = Gtk.TreeView {
        expand = true,
        model = coursesModel,
        Gtk.TreeViewColumn {title = "Id", sort_column_id = 0, { Gtk.CellRendererText {}, { text = 1 } }},
        Gtk.TreeViewColumn {title = "Nombre", sort_column_id = 1, { Gtk.CellRendererText {}, { markup = 2 } }},
    }
    local eva = Gtk.Button {
        label = 'Web del curso',
        image = Gtk.Image { stock = Gtk.STOCK_INFO, icon_size = Gtk.IconSize.BUTTON },
        hexpand = true, halign = 'END', margin_top = 10,
        sensitive = false
    }
    local go = Gtk.Button {
        label = 'Siguiente',
        image = Gtk.Image { stock = Gtk.STOCK_GO_FORWARD, icon_size = Gtk.IconSize.BUTTON },
        halign = 'END', margin_left = 10, margin_top = 10,
        sensitive = false
    }
    grid:attach(label, 0, 0, 2, 1)
    grid:attach(coursesScroll, 0, 1, 2, 1)
    coursesScroll:add(courses)
    grid:attach(eva, 0, 2, 1, 1)
    grid:attach(go, 1, 2, 1, 1)
    courses:get_selection().on_changed = function()
        eva.sensitive = true
        go.sensitive = true
    end
    local evaLinks = {}
    local function selectCourse()
        local row = coursesModel[courses:get_selection():get_selected_rows()[1]]
        app:push(guiClasses(app, {id=row[1], description=row[2]}))
    end
    function courses:on_button_press_event(event)
        if event.type == 'DOUBLE_BUTTON_PRESS' then selectCourse() end
    end
    function eva:on_clicked()
        for i, row in ipairs(courses:get_selection():get_selected_rows()) do
            local url = evaLinks[coursesModel[row][1]]
            if url:match '^https?:' then
                os.execute("xdg-open '" .. evaLinks[coursesModel[row][1]]:gsub("'", "'\\''") .. "'")
            end
        end
    end
    go.on_clicked = selectCourse
    grid.on_realize = function()
        app:title 'OpenFING'
    end
    local msg = Soup.Message.new('GET', 'https://open.fing.edu.uy/data/courses.json')
    local result = Soup.SessionSync {}:send_message(msg)
    if result ~= 200 then
        Gtk.MessageDialog {
            text = 'Error code: ' .. result .. '\nwhile requesting courses',
            message_type = 'ERROR', buttons = 'CLOSE',
            on_response = Gtk.Widget.destroy
        }:run()
    else
        dao:save('courses', json.decode(msg.response_body.data).courses)
    end
    for i, course in ipairs(dao:load 'courses') do
        evaLinks[course.code] = course.eva
        coursesModel:append{course.code, course.name}
    end
    return grid
end



local App = {}
App.__index = App

function App:title(text)
    if text then
        self.window.title = text
    end
    return self.window.title
end

-- gui objects never push themselves, instead they return the widget to be pushed
function App:push(gui, cb_on_pop)
    if #self.children > 0 then
        self.window:remove(self.children[#self.children])
    end
    self.children[#self.children + 1] = {gui = gui, cb_on_pop = cb_on_pop}
    self.window:add(gui)
    self.window:show_all()
end

-- however they do pop by themselves.
function App:pop()
    assert(#self.children > 0)
    local cb_on_pop = self.children[#self.children].cb_on_pop
    self.window:remove(self.children[#self.children].gui)
    self.children[#self.children] = nil
    if #self.children > 0 then
        self.window:add(self.children[#self.children].gui)
    end
    if cb_on_pop then cb_on_pop() end
end

function App:run()
    local res = setmetatable({children={}, titles={}}, self)
    res.window = Gtk.Window {
        default_width = 640, default_height = 480,
        has_resize_grip = true
    }
    function res.window:on_destroy()
        if self == res.window then Gtk.main_quit() end
    end
    res.window:show_all()
    res:push(guiCourses(res))
    Gtk.main()
end

App:run()
-- vi: et sw=4
