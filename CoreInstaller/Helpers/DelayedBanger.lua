function GetSkin(skin)
    SKIN:Bang('[!Delay 500][!CommandMeasure Installer "Get-Skin ' .. skin .. '"]')
end

function finalize(skin)
    print('Bang is fired!')
    SKIN:Bang('[!Delay 500][!CommandMeasure Installer "Finalize-Installation ' .. skin .. '"]')
end