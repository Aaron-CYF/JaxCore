-- A simple UTF-8 validator in Lua. (Tested only with texlua.)
-- Manuel Pégourié-Gonnard, 2009, WTFPL v2.

-- returns true if s is a valid utf-8 sequence according to rfc3629
function is_valid_utf8(str) 
    local len = string.len(str)
    local not_cont = function(b) return b == nil or b < 128 or b >= 192 end
    local i = 0
    local next_byte = function()
        i = i + 1
        return string.byte(str, i)
    end
    while i < len do
        local seq = {}
        seq[1] = next_byte()
        if seq[1] >= 245 then 
            return false, 'Illegal byte '..seq[1]..' at byte '..i
        end
        if seq[1] >= 128 then                   
            local offset -- non-coding bits of the 1st byte
            for l, threshold in ipairs{[2] = 192, 224, 240} do
                if seq[1] >= threshold then     -- >= l byte sequence
                    seq[l] = next_byte()
                    if not_cont(seq[l]) then 
                        return false, 'Illegal continuation byte '..
                        seq[l]..' at byte '..i
                    end
                    offset = threshold
                end
            end
            if offset == nil then
                return false, 'Illegal first byte '..seq[1]..' at byte '..i
            end
            -- compute the code point for some verifications
            local code_point = seq[1] - offset
            for j = 2, #seq do
                code_point = code_point * 64 + seq[j] - 128
            end
            local n -- nominal length of the bytes sequence
            if     code_point <= 0x00007F then n = 1
            elseif code_point <= 0x0007FF then n = 2
            elseif code_point <= 0x00FFFF then n = 3
            elseif code_point <= 0x10FFFF then n = 4
            end
            if n == nil then
                return false, 
                'Code point '..code_point..' too large at byte '..i
            end
            if n ~= #seq then
                return false, 'Overlong encoding at byte '..i
            end
            if code_point >= 0xD800 and code_point <= 0xDFFF then
                return false,  'Code point '..code_point..
                ' reserved for utf-16 surrogate pairs at byte '..i
            end
        end -- if seq[0] >= 128
    end
    return true
end


function coreLog(content)
    SKIN:Bang('!SetVariable', 'Log', ''..SKIN:GetVariable('Log')..'\n'..content..'')
    SKIN:Bang('[!UpdateMeter Log][!Redraw]')
end

function Initialize()
    coreLog('Script.Lua successfully loaded at '..SKIN:GetVariable('Sec.Variant'))
    if SKIN:GetVariable('Sec.Variant'):find('Screen') then
        local coreVer = SKIN:GetVariable('Core.Ver')
        coreLog('Current Core.Ver = '..coreVer..'')
        SKIN:Bang('[!Delay 500][!CommandMeasure ScriptLua "checkTRANS()"]')
    else
        SKIN:Bang('[!CommandMeasure PSRM """Start-Translation -skin \'#JaxCore\' -TargetLanguage "#Set.Lang#" """]')
    end
end

function checkPS()
    psVersion = tonumber(SKIN:GetMeasure('MeasurePSVer'):GetStringValue())
    if psVersion < 5.1 then
        coreLog('[-] Powershell version does not match requirement: 5.1')
    else
        coreLog('[+] Powershell verion >= 5.1')
    end
end

function checkNAME()
    local username = SKIN:GetMeasure('MeasureUser'):GetStringValue()
    local is_valid = is_valid_utf8(username)
    if is_valid then
        coreLog('[+] username "'..username..'" is a valid UTF-8 string')
    else
        coreLog('[i] username "'..username..'" is not a valid UTF-8 string')
    end

    local lastCoreUserName = SKIN:GetVariable('UserNameCheckVariable')
    if username ~= lastCoreUserName then
        coreLog('[i] new user detected, showing welcome screen...')
        SKIN:Bang('[!Delay 100][!CommandMeasure Func "interactionBox(\'tour1\')"][!Refresh]')
    else
        coreLog('[+] user had already installed core before')
        SKIN:Bang('[!ActivateConfig "#JaxCore\\Main" "Home.ini"][!DeactivateConfig]')
    end
end

function checkTRANS()
    local coreLang = SKIN:GetVariable('Set.Lang')
    coreLog('Current Set.Lang = '..coreLang..'')
    if coreLang ~= 'English' then
        coreLog('[i] Last Set.Lang isn\'t English.')
        if psVersion >= 5.1 then
            coreLog('[i] psVersion >= 5.1, proceed translation...')
            SKIN:Bang('[!CommandMeasure Func "interactionBox([[#ROOTCONFIGPATH#Main\\Installation\\Lang.inc]])"][!WriteKeyValue Variables Log """'..SKIN:GetVariable('log'):gsub('\n','#*CRLF*#')..'""" "#ROOTCONFIGPATH#Main\\Installation\\Lang.inc"][!Refresh]')
            print(SKIN:GetVariable('log'):gsub('\n','#CRLF#'))
        end
    else
        coreLog('[+] Last Set.Lang is English, no further translation required.')
        SKIN:Bang('[!Delay 500][!EnableMeasure MeasureUser][!UpdateMeasure MeasureUser]')
    end
end