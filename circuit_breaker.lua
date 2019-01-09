current_endpoint = nil

print("Redis Server Host: ", redis_server)
print("Redis Server Port: ", redis_port)
print("Redis Server Password: ", redis_password)

local redis = require "redis"
local client = redis.connect(redis_server, 6379)
client:auth(redis_password)
response = client:ping() 
print("Redis Server connect Result: ", response)

function GetAdd(hostname)
    local socket = require("socket")
    local ip, resolved = socket.dns.toip(socket.dns.gethostname())
    local ListTab = {}
    for k, v in ipairs(resolved.ip) do
        table.insert(ListTab, v)
    end
    return ListTab
end

function Split(szFullString, szSeparator)  
    local nFindStartIndex = 1  
    local nSplitIndex = 1  
    local nSplitArray = {}  
    while true do  
       local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)  
       if not nFindLastIndex then  
        nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))  
        break  
       end  
       nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)  
       nFindStartIndex = nFindLastIndex + string.len(szSeparator)  
       nSplitIndex = nSplitIndex + 1  
    end  
    return nSplitArray  
end  

local function convertMin2Time(x)
    day = { year = string.sub(x, 0,4), month = string.sub(x, 5,6), day =string.sub(x, 7,8),hour=string.sub(x, 9,10),min=string.sub(x, 11,12) }
    return os.time(day)
end

local function getNewDate(srcDateTime,interval ,dateUnit)  

    --把日期时间字符串转换成对应的日期时间  
    local dt1 = convertMin2Time(srcDateTime) 

    --根据时间单位和偏移量得到具体的偏移数据  
    local ofset=0  

    if dateUnit =='DAY' then  
        ofset = 60 *60 * 24 * interval  

    elseif dateUnit == 'HOUR' then  
        ofset = 60 *60 * interval  

    elseif dateUnit == 'MINUTE' then  
        ofset = 60 * interval  

    elseif dateUnit == 'SECOND' then  
        ofset = interval  
    end  

    --指定的时间+时间偏移量  
    return os.date("%Y%m%d%H%M", dt1 + tonumber(ofset))    
end 

-- 用来计算两个是几点间以分钟为单位的时刻差
local function mindiff(oldtime, newtime )
    local day1 = { year = os.date("%Y",oldtime), month = os.date("%m",oldtime), day =os.date("%d",oldtime),hour=os.date("%H",oldtime),min=os.date("%M",oldtime) }
    local t1 = os.time(day1)
    local day2 = { year = os.date("%Y",newtime), month = os.date("%m",newtime), day =os.date("%d",newtime),hour=os.date("%H",newtime),min=os.date("%M",newtime) }
    local t2 = os.time(day2)
    return (os.difftime(t2, t1)/60)
end

local function is_health(http_code, status_code, response_time, max_response_time)
    if   (tonumber(http_code) ~= 200 and not (tonumber(http_code) >=400 and tonumber(http_code)<500 ) )  or tonumber(status_code) == 500001 or tonumber(response_time)> tonumber(max_response_time) then
        return false
    else
        return true
    end
end

function envoy_on_request(request_handle)
    -- 初始化redis连接
    local redis = require "redis"
    local client = redis.connect(redis_server, redis_port)
    client:auth(redis_password)
    response = client:ping() 
    request_handle:logDebug("AAAAAAAAAAAAAAAAAAa")
    request_handle:logDebug(tostring(response))

    local node_ip = unpack(GetAdd())
    local url = request_handle:headers():get(":path")
    local str_list = Split(url, "?")
    url = url[1]
    local subs = string.sub(url,2,string.len(url))
    current_endpoint = string.gsub(subs,"/","@").."::"..tostring(node_ip)
    request_handle:logDebug(current_endpoint)

    client:hset(current_endpoint, 'cir_count', 1)

    local api_def_info = client:hmget(current_endpoint,'cir_status','min_recovery_time','max_recovery_time','last_lock_time')

    local cir_status, min_recovery_time,max_recovery_time,last_lock_time = api_def_info[1],api_def_info[2],api_def_info[3],api_def_info[4]
    if min_recovery_time == nil then
        client:hset(current_endpoint,'cir_status', 'close')
        cir_status = 'close'
        err_percent = 0.5
        granularity = 1
        rolling_window = 5
        threshold = 20
        max_response_time = 5
        max_recovery_time = 120
        min_recovery_time = 60
    end
    if cir_status == 'open' then 
        local curr_timestemp = os.time()
        local lock_duration =  os.difftime(curr_timestemp,tonumber(last_lock_time))
        if  lock_duration< tonumber(min_recovery_time) then 
            -- 如果小于min_recovery_time， 则直接熔断
            request_handle:logDebug("cir_status: open  &  lock_duration < min_recovery_time")

            client:hset(current_endpoint, 'cir_count', 0)
            local josnstr = '{"code":"100014","message":"Request has been blocked by circuit breaker mechanism!"}'
            request_handle:respond(
                {
                    [":status"] = "200",
                    ["Status-Code"] = 100014,
                    ["x-envoy-upstream-service-time"] = 1,
                    ["content-type"] = "application/json; charset=UTF-8"
                },
                josnstr
            )

        elseif lock_duration < tonumber(max_recovery_time) then
        -- 大于min_recovery_time 小于max_recovery_time 则把熔断器进入半开启的recovery状态
            request_handle:logDebug("cir_status: open  &  min_recovery_time <= lock_duration < max_recovery_time")
            client:hset(current_endpoint,'cir_status','recovery')
        else
            -- 距离最近的一次开启时间已经超过了max_recovery_time，则直接把熔断器关闭，清空窗口信息，开启下一次计数
            request_handle:logDebug("cir_status: open  &  lock_duration > max_recovery_time")
            client:hset(current_endpoint,'cir_status','close')
            local key = ('CIR_BRK::'..url)
            client:del(key)   
        end

    -- 熔断器半开启
    elseif cir_status == 'recovery' then
        request_handle:logDebug("cir_status:  "..cir_status)

        -- 如果当前熔断器是recovery 既半开启状态的时候，且距离最近的一次开启已经超过了max_recovery_time，则直接把熔断器关闭，清空窗口信息，开启下一次计数
        local curr_timestemp = os.time()
        local lock_duration =  os.difftime(curr_timestemp,tonumber(last_lock_time))
        request_handle:logDebug("lock_duration:  "..lock_duration)
        request_handle:logDebug("max_recovery_time:  "..max_recovery_time)
        if lock_duration > tonumber(max_recovery_time) then
            request_handle:logDebug("set cir_status to close.")
            client:hset(api,'cir_status','close')
            local key = ('CIR_BRK::'..url)
            client:del(key)
        end

    end
end


function envoy_on_response(response_handle)
    -- 初始化redis连接
    local redis = require "redis"
    local client = redis.connect(redis_server, redis_port)
    client:auth(redis_password)
    response = client:ping() 
    response_handle:logDebug("BBBADAABABA")
    response_handle:logDebug(tostring(response))

    response_handle:logDebug("current_endpoint: "..current_endpoint)
    http_code = response_handle:headers():get(":status")
    status_code = response_handle:headers():get("status-code")
    response_time = response_handle:headers():get("x-envoy-upstream-service-time")

    

    response_handle:logDebug( "the value to determine cir_count is: "..http_code..' '..status_code)
    if  http_code == '200' and tonumber(cir_count) ==1 and (tonumber(status_code) ~= 500001) and (tonumber(status_code) > 0) and ( tonumber(status_code) < 600000) then 
        client:hset(current_endpoint, 'cir_count', 0)
    end

    if string.find(current_endpoint,'api@v6@data@health@check@get') ~= nil then
        client:hset(current_endpoint, 'cir_count', 0)
    end

    cir_count = client:hget(current_endpoint, 'cir_count')
    if  tonumber(cir_count) == 1 then   
        local curr_timestemp = os.time()
        local curr_time = os.date("%Y%m%d%H%M",curr_timestemp)
        local key = ('CIR_BRK::'..current_endpoint)
        
        local api_def_info = client:hmget(current_endpoint,'cir_status','last_lock_time','max_recovery_time','err_percent','granularity','rolling_window','threshold','max_response_time')
        local cir_status, last_lock_time, max_recovery_time, err_percent ,granularity,rolling_window, threshold ,max_response_time = api_def_info[1],api_def_info[2],api_def_info[3],api_def_info[4],api_def_info[5],api_def_info[6],api_def_info[7],api_def_info[8]
        print(cir_status, last_lock_time, max_recovery_time, err_percent ,granularity,rolling_window, threshold ,max_response_time)
        if min_recovery_time == nil then
            client:hset(current_endpoint,'cir_status', 'close')
            cir_status = 'close'
            err_percent = 0.5
            granularity = 1
            rolling_window = 5
            threshold = 20
            max_response_time = 5
            max_recovery_time = 120
            min_recovery_time = 60
        end
        for _key, _value in pairs(api_def_info) do    
            response_handle:logDebug("CCCCCCCCC".._key.._value)
        end


        local is_ok = is_health(http_code,status_code,response_time,max_response_time)
        response_handle:logDebug('cir_status of '..current_endpoint..': '..cir_status)
        response_handle:logDebug('double check cir_status of '..current_endpoint..': '..client:hget(current_endpoint,'cir_status'))


        --  仅仅当熔断器关闭时，需要启动移动窗口开始计数
        if cir_status == 'close' then

            local n = tonumber(granularity) --每个窗口几分钟
            local m = tonumber(rolling_window)--总共统计几个窗口
            --local threshold = 10
            local shift = 0  --新的调用间隔几分钟

            local field = ''

            if tonumber(client:hget(key,'timeline')) ==1 then

                shift = mindiff(tonumber(client:hget(key,'timeline')),tonumber(curr_timestemp))
                response_handle:logDebug('time shift from the first rolling window(mins): '..shift)
                local origin_time = os.date("%Y%m%d%H%M",tonumber(client:hget(key,'timeline')))
                -- 判断是否需要新建时间窗
                if shift < n*m then
                 --  完全可以使用已有的时间窗，无需创建新的时间窗
                    response_handle:logDebug('kept all the rolling windows we currently have.')
                    gap = math.floor((shift)/n)
                    -- 这个是需要被的key --
                    --   print(time+gap*n..'-'..time+(gap+1)*n-1)
                    field = (getNewDate(origin_time,gap*n,'MINUTE')..'-'..getNewDate(origin_time,(gap+1)*n-1,'MINUTE'))
                    client:hincrby(key, (field..'::TOTAL'), 1)
                    if not is_ok then
                        client:hincrby(key, (field..'::ERROR'), 1)
                    end

                else

                    -- 判断是否可以新建全部的时间窗
                    if (shift > (n*m-1 + n*(m-1))) then
                        response_handle:logDebug('Rebuild all the rolling windows and remove all the expired windows.')
                        -- ，删除所有老窗口
                        client:del(key)
                        --新建全部窗口
                        for i = 0,m-1 do
                            field = (getNewDate(curr_time,i*n,'MINUTE')..'-'..getNewDate(curr_time,(i+1)*n-1,'MINUTE'))
                            client:hincrby(key, (field..'::TOTAL'), 0)
                            client:hincrby(key, (field..'::ERROR'), 0)
                        --    print(new_time+i*n..'-'..new_time+(i+1)*n-1)
                        end
                            field = (getNewDate(curr_time,0,'MINUTE')..'-'..getNewDate(curr_time,n-1,'MINUTE'))
                            client:hincrby(key, (field..'::TOTAL'), 1)
                            if not is_ok then
                                client:hincrby(key, (field..'::ERROR'), 1)
                            end

                        --  设置新的起点时间线
                        client:set(key,'timeline',curr_timestemp)

                    else
                        -- 只需要创建部分新窗口，同时删除部分老窗口
                        response_handle:logDebug('Setup some new rolling windows and remove the corresponding olds')
                        local blank_window = math.floor((shift-n*m)/n)+1
                        for i = 0+blank_window,m-1+blank_window do
                            field = (getNewDate(origin_time,i*n,'MINUTE')..'-'..getNewDate(origin_time,(i+1)*n-1,'MINUTE'))
                            client:hincrby(key, (field..'::TOTAL'), 0)
                            client:hincrby(key, (field..'::ERROR'), 0)
                      --      print(time+i*n..'-'..time+(i+1)*n-1)
                        end

                        for i = 0, blank_window-1 do
                            field = (getNewDate(origin_time,i*n,'MINUTE')..'-'..getNewDate(origin_time,(i+1)*n-1,'MINUTE'))
                            client:del(key, (field..'::TOTAL'))
                            client:del(key, (field..'::ERROR'))
                  --          print(time+i*n..'-'..time+(i+1)*n-1)
                        end
                        --  设置新的起点时间线
                        client:set(key,'timeline',convertMin2Time(getNewDate(origin_time,n*blank_window,'MINUTE')))

                        -- 在正确的时间窗计数 
                        field = (getNewDate(origin_time,(m-1+blank_window)*n,'MINUTE')..'-'..getNewDate(origin_time,(m-1+blank_window+1)*n-1,'MINUTE'))
                        client:hincrby(key, (field..'::TOTAL'), 1)
                        if not is_ok then
                            client:hincrby(key, (field..'::ERROR'), 1)
                        end

                    end   
                end

            else
                response_handle:logDebug('Initial all the rolling windows since cir_status has been changed.')
                for i = 0,m-1 do
                    field = (getNewDate(curr_time,i*n,'MINUTE')..'-'..getNewDate(curr_time,(i+1)*n-1,'MINUTE'))
                    client:hincrby(key, (field..'::TOTAL'), 0)
                    client:hincrby(key, (field..'::ERROR'), 0)     
                end

                field = (curr_time..'-'..getNewDate(curr_time,n-1,'MINUTE'))
                client:hincrby(key, (field..'::TOTAL'), 1)
                if not is_ok then
                    client:hincrby(key, (field..'::ERROR'), 1)
                end
                client:hset(key,'timeline',curr_timestemp)
            end

            -- 更新窗口计数后， 开始统计当前的数量
            local total = 0
            local err = 0
            local hkeys=client:hkeys(key)

            
            for i =1, table.getn(hkeys) do
                response_handle:logDebug("hahahh"..hkeys[i])
                if string.find(hkeys[i],'TOTAL') ~= nil then
                    total = total + tonumber(client:hget(key,hkeys[i]))
                elseif string.find(hkeys[i],'ERROR') ~= nil then
                    err =err + tonumber(client:hget(key,hkeys[i]))
                end
            end
            -- 仅仅当统计周期内，总调用数量大于基本阈值时，才开始检查是否需要触发熔断
            response_handle:logDebug('total: '..total)
            response_handle:logDebug('err: '..err)
            response_handle:logDebug('threshold: '..threshold)
            if total >  tonumber(threshold) then
                -- 错误比大于设定的比例，打开熔断器，触发熔断，记录熔点开始时间，清空时间窗
                if (err/total) > tonumber(err_percent) then

                    client:hset(current_endpoint, 'cir_status','open')
                    client:hset(current_endpoint, 'last_lock_time',curr_timestemp)
                    client:del(key)

                end
            end
        else
            -- 如果熔断器状态在 recovery 状态， 说明过了 min_recovery_time 且不到 max_recovery_time 
            if cir_status == 'recovery' then
                local lock_duration = os.difftime(curr_timestemp,tonumber(last_lock_time))

                if is_ok then
                    response_handle:logDebug('The recent request is healthy.')
                    math.randomseed(curr_timestemp)  
                    ram = math.random()
                    -- 根据本次请求的结果，如果正确，有概率直接关闭熔断器。
                    if ram < ((lock_duration)/tonumber(max_recovery_time)) then
                        response_handle:logDebug('Lucky! the cir_status has been changed to close.')
                        client:hset(current_endpoint, 'cir_status','close')
                        client:del(key)
                    else
                        response_handle:logDebug('Too bad, the cir_status has been kept with recovery.')
                    end

                else
                    --根据本次请求的结果，如果出错，立即回复open状态， 
                    response_handle:logDebug('The recent request is unhealthy, reopen the lock')
                    client:hset(current_endpoint, 'cir_status','open')
                    client:hset(current_endpoint, 'last_lock_time',curr_timestemp)
                end
            end

        end
    end

end