--!nonstrict
-- Runs zmk_battery.py and publishes the result as the "zmk" state key for the bar widget and the panel.
-- Other entries request work by setting "zmk.cmd" to { id = <unique>, action = "refresh" | "select", device = <name> }.

local REFRESH_MINUTES = 10
local SCRIPT_TIMEOUT_MS = 60000

local dataDir = noctalia.pluginDataDir()
local deviceFile = dataDir and (dataDir .. "/device.txt") or nil

local function loadDevice()
  if not deviceFile then
    return ""
  end
  return noctalia.string.trim(noctalia.readFile(deviceFile) or "")
end

-- Last good levels survive failed reads, e.g. while ZMK Studio holds the port
local status = {
  reading = false,
  name = "",
  devices = {},
  sides = {},
  error = "reading...",
  updatedAt = 0,
  selected = loadDevice(),
}

local function publish()
  noctalia.state.set("zmk", status)
end

local function apply(stdout)
  local result = noctalia.json.decode(noctalia.string.trim(stdout or ""))
  if type(result) ~= "table" then
    status.error = "bad output: " .. (stdout or "")
    return
  end
  status.devices = result.devices or {}
  if result.ok then
    status.sides = result.sides or {}
    status.name = result.name or ""
    status.error = ""
    status.updatedAt = os.time()
  else
    status.error = result.error or "unknown error"
  end
end

local function refresh()
  if status.reading then
    return
  end
  local argv = { "python3", "-I", noctalia.pluginDir() .. "/zmk_battery.py" }
  if status.selected ~= "" then
    table.insert(argv, "--device")
    table.insert(argv, status.selected)
  end
  status.reading = true
  publish()
  local started = noctalia.runAsync(argv, function(res)
    status.reading = false
    if res.timedOut then
      status.error = "timed out reading the dongle"
    elseif res.stdout == nil or res.stdout == "" then
      status.error = noctalia.string.trim(res.stderr or "") ~= "" and noctalia.string.trim(res.stderr) or "no output"
    else
      apply(res.stdout)
    end
    publish()
  end, SCRIPT_TIMEOUT_MS)
  if not started then
    status.reading = false
    status.error = "could not start python3"
    publish()
  end
end

local function selectDevice(name)
  status.selected = name or ""
  if deviceFile then
    noctalia.writeFile(deviceFile, status.selected)
  end
  refresh()
end

noctalia.state.watch("zmk.cmd", function(cmd)
  if type(cmd) ~= "table" then
    return
  end
  if cmd.action == "select" then
    selectDevice(cmd.device)
  elseif cmd.action == "refresh" then
    refresh()
  end
end)

function update()
  refresh()
end

function onIpc(event, payload)
  if event == "refresh" then
    refresh()
  elseif event == "select" then
    selectDevice(payload)
  end
end

noctalia.setUpdateInterval(REFRESH_MINUTES * 60 * 1000)
publish()
refresh()
