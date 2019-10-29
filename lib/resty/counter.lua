local ngx_shared = ngx.shared


local _M = {}
local mt = { __index = _M }

-- local cache of counters increments
local increments = {}
-- boolean flags of per worker sync timers
local timer_started = {}

local id

local function sync(_, self)
  local err, _
  for k, v in pairs(self.increments) do
    self.increments[k] = nil
    _, err, _ = self.dict:incr(k, v, 0)
    if err then
      ngx.log(ngx.WARN, "error increasing counter in shdict key: ", k, ", err: ", err)
    end
  end
end

function _M.new(shdict_name, sync_interval)
  id = ngx.worker.id()

  if not ngx_shared[shdict_name] then
    return nil, "shared dict \"" .. (shdict_name or "nil") .. "\" not defined"
  end

  sync_interval = tonumber(sync_interval)
  if not sync_interval or sync_interval < 0 then
    return nil, "expect sync_interval to be a positive number"
  end

  if not increments[shdict_name] then
    increments[shdict_name] = {}
  end

  local self = setmetatable({
    dict = ngx_shared[shdict_name],
    sync_interval = sync_interval,
    increments = increments[shdict_name],
  }, mt)

  if not timer_started[shdict_name] then
    ngx.log(ngx.DEBUG, "start timer for shdict ", shdict_name, " on worker ", id)
    ngx.timer.every(sync_interval, sync, self)
    timer_started[shdict_name] = true
  end

  return self
end

function _M:incr(key, step)
  step = step or 1
  local v = self.increments[key]
  if v then
    step = step + v
  end

  self.increments[key] = step
  return true
end

function _M:reset(key, number)
  if not number then
    return nil, "expect a number at #2"
  end
  return self.dict:incr(key, -number, number)
end

function _M:get(key)
  return self.dict:get(key)
end

function _M:get_keys(max_count)
  return self.dict:get_keys(max_count)
end

return _M