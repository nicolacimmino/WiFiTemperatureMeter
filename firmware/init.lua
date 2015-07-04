-- Firmware for ESP8266 reporting room temperature and battery level to Thingspeak.
--  Copyright (C) 2015 Nicola Cimmino
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--   This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see http://www.gnu.org/licenses/.
--
-- This code has been tested on an ESP-12 module running NodeMCU 0.9.6-dev_20150704
-- See http://nodemcu.com/index_en.html
--
-- You can have a look at the public JSON feed of the device under test here:
--  https://api.thingspeak.com/channels/2479/feed.json
--
-- Or at live graphs of the device battery and room temperature here:
--  http://nicolacimmino.com/WiFiTemperature.html

  -- Thinkgspeak channel write key
  ts_channel_key = "CHANNELKEY"
  
  -- WiFi AP Credentials
  WiFi_ssid = "SSID"
  WiFi_pass = "PASSWORD"
  
  -- Green LED
  gpio.mode(6,gpio.OUTPUT)

  -- We will be running init.lua and when done go back to sleep
  -- this gives us the possibility to bail out and get a chance
  -- to upload a new script. Just send a char to serial.  
  uart.on("data", 1,  
    function(data) 
      file.remove("init.lua")
      tmr.stop(1)
      tmr.stop(2)      
      uart.on("data")  
    end , 0)
  
  -- Setup a watchdog, if something goes terribly wrong
  -- we still have a chance to reset rather than sitting
  -- there and drain batteries.
  tmr.alarm(2,60000,0, function() node.restart() end)

  -- Prevent auto-reconnect as we cannot read ADC while connected
  wifi.sta.autoconnect(0)
  wifi.sta.disconnect()

  -- Give a sign of life so we know something is going on
  gpio.write(6,gpio.HIGH)

  -- Get supply voltage
  voltage = adc.readvdd33()
  if voltage == nil then
  voltage = 0
  end
  voltage = voltage / 1000
  print(voltage)
 
  -- Get DS18B20 temperature reading.
  -- This assumes a single sensor, the library can
  -- handle multiple as well.
  local tempSensor = require("ds18b20")
  tempSensor.setup(2)
  temp_c = tempSensor.read(nil,tempSensor.C)
  if temp_c == nil then
    tmp_c = 0
  end
  print(temp_c)
  tempSensor=nil
  ds18b20 = nil
  package.loaded["ds18b20"]=nil
  
  -- Attempt WiFi set-up
  wifi.setmode(wifi.STATION)
  wifi.sta.config(WiFi_ssid, WiFi_pass)
  wifi.sta.connect()
  
  function checkNetwork()
    if wifi.sta.getip() == nil then
      print("Waiting network")
      return
    end
    tmr.stop(1)
    print("Network up")  
    sendData()
  end

  -- If processing here becomes lengthy remember to
  -- reset the watchdog on timer 2 from time to time.
  function sendData()      
    local conn=net.createConnection(net.TCP, 0)
    conn:on("receive", function(conn, payload) responseReceived(payload) end )
    conn:connect(80,"184.106.153.149")
    conn:send("GET /update?key=" .. ts_channel_key .. "&field1=" .. voltage 
        .. "&field2=" .. temp_c
        .. " HTTP/1.1\r\nHost: api.thingspeak.com\r\n"
        .."Connection: close\r\nAccept: */*\r\n\r\n")
  end
 
  -- We got a reply from Thingspeak
  -- LED off and deep sleep mode for 60s
 function responseReceived(data)
  wifi.sta.autoconnect(0)
  wifi.sta.disconnect()
  gpio.write(6,gpio.LOW)
  tmr.stop(2) 
  node.dsleep(60000000, 4);
 end

  -- Check we got network every 2 seconds.
  tmr.alarm(1,2000,1, function() checkNetwork() end)
