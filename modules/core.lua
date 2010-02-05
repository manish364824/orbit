
local orbit = require "orbit"
local model = require "orbit.model"
local routes = require "orbit.routes"
local util = require "modules.util"
local blocks = require "modules.blocks"
local themes = require "modules.themes"
local lfs = require "lfs"

local core = {}

local R = orbit.routes.R

local methods = {}

function methods:layout(web, inner_html)
  local layout_template = self.theme:load("layout.html")
  if layout_template then
    return layout_template:render(web, { inner = inner_html })
  else
    return inner_html
  end
end

function methods:home(web)
  local home_template = self.theme:load("pages/home.html")
  if home_template then
    return self:layout(web, home_template:render(web))
  else
    return self.not_found(web)
  end
end

function methods:view_node(web, node, raw)
  local type = node.type
  local template
  if node.nice_id then
    template = self.theme:load("pages/" .. node.nice_id:gsub("/", "-") .. ".html")
  end
  template = template or self.theme:load("pages/" .. type .. ".html")
  if template then
    if raw then
      return template:render(web, { node = node })
    else
      return self:layout(web, template:render(web, { node = node }))
    end
  else
    return self.not_found(web)
  end
end

function methods:view_node_id(web, params)
  local id = tonumber(params.id)
  local node = self.nodes:find(id)
  if node then
    return self:view_node(web, node)
  else
    return self.not_found(web)
  end
end

function methods:view_node_id_raw(web, params)
  local id = tonumber(params.id)
  local node = self.nodes:find(id)
  if node then
    return self:view_node(web, node, true)
  else
    return self.not_found(web)
  end
end

function methods:view_nice(web, params)
  local nice_handle = "/" .. params.splat[1]
  local node = self.nodes:find_by_nice_id(nice_handle)
  if node then
    return self:view_node(web, node)
  else
    return self.reparse
  end
end

function methods:view_node_type(web, params)
  local type, id = params.type, tonumber(params.id)
  if self.nodes.types[type] and id then
    local node = self.nodes[type]:find(id)
    if node then
      return self:view_node(web, node)
    end
  end
  return self.reparse
end

function methods:view_node_type_raw(web, params)
  local type, id = params.type, tonumber(params.id)
  if self.nodes.types[type] and id then
    local node = self.nodes[type]:find(id)
    if node then
      return self:view_node(web, node, true)
    end
  end
  return self.reparse
end

function core.load_plugins(app)
  for _, file in ipairs(app.config.plugins or {}) do
    local plugin = dofile(app.real_path .. "/plugins/" .. file)
    app.plugins[plugin.name] = plugin.new(app)
  end
end

function methods:block_template(block)
  local tmpl, err = self.theme:load("blocks/" .. block .. ".html")
  return tmpl
end

function core.new(app)
  app = orbit.new(app)
  for k, v in pairs(methods) do
    app[k] = v
  end
  app.blocks = { protos = blocks, instances = {} }
  app.config = util.loadin(app.real_path .. "/config.lua")
  if not app.config then
    error("cannot find config.lua in " .. app.real_path)
  end
  app.theme = themes.new(app, app.config.theme, app.real_path .. "/themes")
  if not app.theme then
    error("theme " .. app.config.theme .. " not found")
  end
  app.nodes = { types = {} }
  app.plugins = {}
  app.routes = { 
    { pattern = R'/', handler = app.home, method = "get" },
    { pattern = R'/node/:id', handler = app.view_node_id, method = "get" },
    { pattern = R'/node/:id/raw', handler = app.view_node_id_raw, method = "get" },
    { pattern = R'/:type/:id', handler = app.view_node_type, method = "get" },
    { pattern = R'/:type/:id/raw', handler = app.view_node_type_raw, method = "get" },
    { pattern = R'/*', handler = app.view_nice, method = "get" },
  }
  local luasql = require("luasql." .. app.config.database.driver)
  local env = luasql[app.config.database.driver]()
  app.mapper.logging = true
  app.mapper.conn = env:connect(unpack(app.config.database.connection))
  app.mapper.driver = model.drivers[app.config.database.driver]
  app.mapper.schema = { entities = {} }
  core.load_plugins(app)
  for name, proto in pairs(app.config.blocks) do
    app.blocks.instances[name] = app.blocks.protos[proto[1]](app, proto.args, app:block_template(name))
  end
  for _, route in ipairs(app.routes) do
    app["dispatch_" .. route.method](app, function (...) return route.handler(app, ...) end, route.pattern)
  end
end

return core
