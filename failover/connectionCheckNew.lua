require "ubus"
require "uloop"

local socket = require("socket")
local bit = require("bit")

connectionCheckInterval = 5000 --Interval for checking whether the connection went down in miliseconds
connectionStatus = true --Global variable for last known status of the connection to the internet

function pingConnectivity(ip)
    local pingCmd = "ping -c 4 -w 2 -q " .. ip .. " 2> /dev/null" --Discard errors

    local pingOut = io.popen(pingCmd, "r")

    local pingResult = pingOut:read("*a")
    pingOut:close()

    local pingLoss = string.match(pingResult, "%d+%%") --Matches any digits folowed by a percentage sign ddd% which signifies packet loss

    if pingLoss == nil then
        return false
    end

    local percentage = string.match(pingLoss, "%d+")

    if percentage == nil then
        return false
    end

    if tonumber(percentage) <= 75 then
        return true
    else
        return false
    end

end

function pingConnectivityInterface(ip, interface)

    if not interface then
        return false
    end

    local pingCmd = "ping -c 4 -w 2 -q -I " .. interface .. " " .. ip .. " 2> /dev/null" --Discard errors

    local pingOut = io.popen(pingCmd, "r")

    local pingResult = pingOut:read("*a")
    pingOut:close()

    local pingLoss = string.match(pingResult, "%d+%%") --Matches any digits folowed by a percentage sign ddd% which signifies packet loss

    if pingLoss == nil then
        return false
    end

    local percentage = string.match(pingLoss, "%d+")

    if percentage == nil then
        return false
    end

    if tonumber(percentage) <= 75 then
        return true
    else
        return false
    end

end

function httpConnectivity(host) --Checking connectivity using lua sockets by trying to establish http connection with a host

    if not host then
        return false
    end
    
    local port = 80
    
    local client = socket.tcp()

    client:settimeout(2)
    
    local connection = client:connect(host, port)

    if connection then
        client:close()
        return true
    else
        client:close()
        return false
    end

end

function checkConnection()
    local isConnected = httpConnectivity("google.com") -- Try connecting to google.com
    
    if not isConnected then
        isConnected = pingConnectivity("1.1.1.1") -- Try pinging cloudflare DNS
    end

    return isConnected

end

function checkInterfaceConnection(interface)
    local isConnected = pingConnectivityInterface("1.1.1.1", interface) -- Try pinging cloudflare DNS
    
    if not isConnected then
        isConnected = pingConnectivityInterface("8.8.8.8", interface) -- Try pinging google DNS
    end

    return isConnected
end


uloop.init()

local ubusConnection = ubus.connect()

if not ubusConnection then
        print("Failed to connect to ubus")
        os.exit(false)
end


local connectivityService = {
    connectivity = {
        hasConnection = {
            function(req, msg)
                if connectionStatus then
                    ubusConnection:reply(req, {connected="True"})    
                else
                    ubusConnection:reply(req, {connected="False"}) 
                end
                
            end, {}
        },
        interfaceConnection = {
            function(req, msg)
                if checkInterfaceConnection(msg.ifName) then
                    ubusConnection:reply(req, {connected="True"})   
                else
                    ubusConnection:reply(req, {connected="False"}) 
                end
            end, {ifName = ubus.STRING}
        }
    }
}

ubusConnection:add(connectivityService)


local connectionTimer

function ubusConnectionEvent()
    local newConnectionStatus = checkConnection()

    if newConnectionStatus == connectionStatus then --Exit without renewing connection status because it did not change since last
        connectionTimer:set(connectionCheckInterval)
        return
    end

    if newConnectionStatus then --Notify subscribers of changes
        ubusConnection:notify(connectivityService.connectivity.__ubusobj, "connectivity.alarm", {connected="True"})
    else
        ubusConnection:notify(connectivityService.connectivity.__ubusobj, "connectivity.alarm", {connected="False"})
    end

    connectionStatus = newConnectionStatus
    connectionTimer:set(connectionCheckInterval)
    
end



connectionTimer = uloop.timer(ubusConnectionEvent)
connectionTimer:set(connectionCheckInterval)

uloop.run()


