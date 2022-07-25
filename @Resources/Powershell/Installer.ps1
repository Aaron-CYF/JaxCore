$ErrorActionPreference = 'SilentlyContinue'

$root = $RmAPI.VariableStr("SKINSPATH") + "#CoreInstallerCache"
function InitInstall { 
    $url = $RmAPI.VariableStr('DownloadLink')
    $name = $RmAPI.VariableStr('DownloadName')
    $RmAPI.Bang("[!DeactivateConfig `"#JaxCore\Accessories\GenericInteractionBox`"][!CommandMeasure Func `"interactionBox('Install', '$name', '$url')`"]")
}
# ---------------------------------------------------------------------------- #
#                                   Functions                                  #
# ---------------------------------------------------------------------------- #

function Get-IniContent ($filePath) {
    $ini = [ordered]@{}
    if (![System.IO.File]::Exists($filePath)) {
        throw "$filePath invalid"
    }
    # $section = ';ItIsNotAFuckingSection;'
    # $ini.Add($section, [ordered]@{})

    foreach ($line in [System.IO.File]::ReadLines($filePath)) {
        if ($line -match "^\s*\[(.+?)\]\s*$") {
            $section = $matches[1]
            $secDup = 1
            while ($ini.Keys -contains $section) {
                $section = $section + '||ps' + $secDup
            }
            $ini.Add($section, [ordered]@{})
        }
        elseif ($line -match "^\s*;.*$") {
            $notSectionCount = 0
            while ($ini[$section].Keys -contains ';NotSection' + $notSectionCount) {
                $notSectionCount++
            }
            $ini[$section][';NotSection' + $notSectionCount] = $matches[1]
        }
        elseif ($line -match "^\s*(.+?)\s*=\s*(.+?)$") {
            $key, $value = $matches[1..2]
            $ini[$section][$key] = $value
        }
        else {
            $notSectionCount = 0
            while ($ini[$section].Keys -contains ';NotSection' + $notSectionCount) {
                $notSectionCount++
            }
            $ini[$section][';NotSection' + $notSectionCount] = $line
        }
    }

    return $ini
}

function Set-IniContent($ini, $filePath) {
    $str = @()

    foreach ($section in $ini.GetEnumerator()) {
        if ($section -ne ';ItIsNotAFuckingSection;') {
            $str += "[" + ($section.Key -replace '\|\|ps\d+$', '') + "]"
        }
        foreach ($keyvaluepair in $section.Value.GetEnumerator()) {
            if ($keyvaluepair.Key -match "^;NotSection\d+$") {
                $str += $keyvaluepair.Value
            }
            else {
                $str += $keyvaluepair.Key + "=" + $keyvaluepair.Value
            }
        }
    }

    $finalStr = $str -join [System.Environment]::NewLine

    $finalStr | Out-File -filePath $filePath -Force -Encoding unicode
}

function debug {
    param(
        [Parameter()]
        [string]
        $message
    )

    $RmAPI.Bang("[!Log `"`"`"CoreInstaller: " + $message + "`"`"`" Debug]")
}

function post-prog {
    param(
        [Parameter()]
        [string]
        $message
    )
    $RmAPI.Bang("[!SetVariable InstallText `"`"`"" + $message + "`"`"`"][!UpdateMeterGroup Progress][!Redraw]")
    
}

function Get-Webfile ($url, $dest) {
    debug "Downloading $url`n"
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(5000)
    $response = $request.GetResponse()
    $length = $response.get_ContentLength()
    $responseStream = $response.GetResponseStream()
    $destStream = New-Object -TypeName System.IO.FileStream -ArgumentList $dest, Create
    $buffer = New-Object byte[] 100KB
    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count

    while ($count -gt 0) {
        $RmAPI.Bang("[!CommandMeasure s.CircleBarHelper `"DrawCircleBar($([System.Math]::Round(($downloadedBytes / $length) * 100,0)))`"][!SetOption ProgressBar.String Text `"$([System.Math]::Round(($downloadedBytes / $length) * 100,0))%`"][!UpdateMeterGroup Progress][!Redraw]")
        $destStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer, 0, $buffer.length)
        $downloadedBytes += $count
    }

    debug "`nDownload of `"$dest`" finished."
    $destStream.Flush()
    $destStream.Close()
    $destStream.Dispose()
    $responseStream.Dispose()
}

function New-Cache {

    [System.IO.Directory]::CreateDirectory("$root") | Out-Null
    Get-ChildItem "$root" | ForEach-Object {
        Remove-Item $_.FullName -Force -Recurse
    }
}

# ---------------------------------------------------------------------------- #
#                                    Actions                                   #
# ---------------------------------------------------------------------------- #
function Install {
    $url = $RmAPI.VariableStr('sec.arg2')
    $name = $RmAPI.VariableStr('sec.arg1')
    $outPath = "$root/$name.rmskin"
    # -------------------------------- Clear cache ------------------------------- #
    New-Cache
    # ---------------------------- Stop ahk processes ---------------------------- #
    $process = Get-Process 'Rainmeter'
    $ppid = $process.Id
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ppid } | ForEach-Object { Stop-Process $_.ProcessId }
    # ------------------------------- Download file ------------------------------ #
    Get-Webfile $url $outPath
    # ------------------------------- Extract file ------------------------------- #
    post-prog "Expanding archive"
    Rename-Item -Path "$outPath" -NewName "$name.zip"
    Expand-Archive -Path "$root\$name.zip" -DestinationPath "$root\Unpacked\" -Force -Verbose
    post-prog "Installing..."
    
    # ---------------------------- Start installation ---------------------------- #
    debug "Starting installation"
    $rmprocess_object = Get-Process Rainmeter
    $rmprocess_id = $rmprocess_object.id
    $Ini = Get-IniContent "$root\Unpacked\RMSKIN.ini"
    
    Add-Type -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CallingConvention = CallingConvention.Winapi)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool IsWow64Process(
    [In] System.IntPtr hProcess,
    [Out, MarshalAs(UnmanagedType.Bool)] out bool wow64Process);
'@ -Name NativeMethods -Namespace Kernel32

    $Ini["rmskin"]["RainmeterPluginsBit"] = "32bit"
    Get-Process -Id $rmprocess_id | Foreach {
        $is32Bit=[int]0 
        if ($_.Handle -ne $null) {
            if ([Kernel32.NativeMethods]::IsWow64Process($_.Handle, [ref]$is32Bit)) { 
                $Ini["rmskin"]["RainmeterPluginsBit"] = "$(if ($is32Bit) {'32bit'} else {'64bit'})"
            } else {
                $Ini["rmskin"]["RainmeterPluginsBit"] = "32bit"
            }    
        }
    }

    $Ini["rmskin"]["RainmeterPath"] = "$($RmAPI.VariableStr('SETTINGSPATH'))"
    $Ini["rmskin"]["RainmeterExePath"] = "$($RmAPI.VariableStr('PROGRAMPATH'))"
    Set-IniContent $Ini "$root\Unpacked\RMSKIN.ini"

    Copy-Item -Path "$($RmAPI.VariableStr('@'))Powershell\InstallerProcess.ps1" -Destination "$root\InstallerProcess.ps1"
    If ($name -match "^JaxCore") {$RmAPI.Bang("[!WriteKeyValue `"$($RmAPI.VariableStr('CURRENTCONFIG'))`" Active 0 `"$($RmAPI.VariableStr('SETTINGSPATH'))Rainmeter.ini`"]")}
    cmd /c start powershell -command "Get-Process Rainmeter | Stop-Process; `$root='$root\Unpacked';`$Script='$($root -replace ' ','` ')\InstallerProcess.ps1';`$Script | Invoke-Expression"
}

function FinishInstall {
    New-Cache
    $RmAPI.Bang('[!DeactivateConfig]')
}

function CheckForDLC {
    If ([String]::IsNullOrWhiteSpace((Get-content "$($RmAPI.VariableStr('SKINSPATH'))..\CoreData\@DLCs\InstalledDLCs.inc"))) {
        $RmAPI.Bang('[!ActivateConfig "#JaxCore\Main" "Settings.Ini"][!DeactivateConfig]')
    } else {
        $Ini = Get-IniContent -filePath "$($RmAPI.VariableStr('SKINSPATH'))..\CoreData\@DLCs\InstalledDLCs.inc"
        $InstalledSkin = $RmAPI.VariableStr('SKIN.NAME')
        for ($i = 0; $i -lt $Ini['Variables'].Keys.Count; $i++) { 
            debug $Ini['Variables'].Keys[$i]
            if ($Ini['Variables'].Keys[$i] -match $InstalledSkin) {
                debug "Found $InstalledSkin"
                $RmAPI.Bang('[!WriteKeyValue Variables Sec.Page "2" "'+$($RmAPI.VariableStr('ROOTCONFIGPATH'))+'Main\Home.ini"][!WriteKeyValue Variables Page.SubPage "1" "'+$($RmAPI.VariableStr('ROOTCONFIGPATH'))+'CoreShell\Home\Page2.inc"][!WriteKeyValue Variables Page.Complete_Reinstallation "1" "'+$($RmAPI.VariableStr('ROOTCONFIGPATH'))+'CoreShell\Home\Page2.inc"][!ActivateConfig "#JaxCore\Main" "Home.Ini"][!DeactivateConfig]')
                Return
            } else {
                debug "Not Found"
            }
        }
        $RmAPI.Bang('[!ActivateConfig "#JaxCore\Main" "Settings.Ini"][!DeactivateConfig]')
        # [!ActivateConfig "'+$RmAPI.VariableStr('Skin.Name')+'\Main"]
    }
    $RmAPI.Bang('[!ActivateConfig "#JaxCore\Main" "Settings.Ini"][!DeactivateConfig]')
}

function GenCoreData {
    $SkinsPath = $RmAPI.VariableStr('SKINSPATH')
    $SkinName = $RmAPI.VariableStr('Skin.Name')
    $SkinVer = $RmAPI.VariableStr('Version')
    If (Test-Path -Path "$SkinsPath..\CoreData") {
        $RmAPI.Log("Found coredata in programs")

        If (Test-Path -Path "$SkinsPath$SkinName\@Resources\@Structure") {
            $RmAPI.Log("Available CoreData structure for $SkinName")
            If (-not (Test-Path -Path "$SkinsPath..\CoreData\$SkinName\$SkinVer.txt")) {
                $RmAPI.Log("Generating: Can't find $SkinVer.txt file in CoreData of $SkinName")
                Robocopy "$SkinsPath$SkinName\@Resources\@Structure" "$SkinsPath..\CoreData\$SkinName" /E /XC /XN /XO
                New-Item -Path "$SkinsPath..\CoreData\$SkinName" -Name "$SkinVer.txt" -ItemType "file"
            }
            else {
                $RmAPI.Log("CoreData for $SkinName is already generated")
            }
        }
        else {
            $RmAPI.Log("$SkinName doesn't require creation of CoreData")
        }
    }
    else {
        $RmAPI.Log("Failed to find coredata in programs, generating")
        New-Item -Path "$SkinsPath..\" -Name "CoreData" -ItemType "directory"
        $RmAPI.Bang('[!Refresh]')
    }
}

function DuplicateSkin {
    param (
        [string]$DuplicateName = 'CloneSkinName'
    )
    $SkinsPath = $RmAPI.VariableStr('SKINSPATH')
    $Resources = $RmAPI.VariableStr('@')
    $SkinName = $RmAPI.VariableStr('Sec.arg1')

    If (Test-Path -Path "$SkinsPath$DuplicateName") {
        $RmAPI.Log("Folder already exits")
    }
    else {
        $RmAPI.Log("Duplicating to $DuplicateName")
        Copy-Item -Path "$SkinsPath$SkinName\" -Destination "$SkinsPath$DuplicateName\" -Recurse
        New-Item -Path "$SkinsPath$DuplicateName\@Resources\" -Name "IsClone.txt" -ItemType "file"
    }
    $RmAPI.Bang("[!WriteKeyValue Rainmeter OnRefreshAction `"`"`"[!WriteKeyValue Rainmeter OnRefreshAction `"#*Sec.DefaultStartActions*#`"][!DeactivateConfig]`"`"`"][!WriteKeyValue Variables Skin.Name $DuplicateName `"$($Resources)SecVar.inc`"][!WriteKeyValue Variables Skin.Set_Page Info `"$($Resources)SecVar.inc`"][!WriteKeyValue `"#JaxCore\Main`" Active 1 `"$($RmAPI.VariableStr('SETTINGSPATH'))Rainmeter.ini`"][`"$($Resources)Addons\RestartRainmeter.exe`"]")

}

function Remove-Section($SkinName) {

    $Ini = Get-IniContent -filePath "$($RmAPI.VariableStr('SETTINGSPATH'))Rainmeter.ini"
    $pattern = "^$SkinName"
    [string[]]$Ini.Keys | Where-Object { $_ -match $pattern } | ForEach-Object { 
        debug "Detected section [$_] in Rainmeter.ini, removing"
        $Ini.Remove($_)
    }
    Set-IniContent -ini $Ini -filePath "$($RmAPI.VariableStr('SETTINGSPATH'))Rainmeter.ini"

}

function Uninstall {
    $SkinsPath = $RmAPI.VariableStr('SKINSPATH')
    $Resources = $RmAPI.VariableStr('@')
    $SkinName = $RmAPI.VariableStr('Sec.arg1')
    If (Test-Path -Path "$SkinsPath..\CoreData\$SkinName") {
        Remove-Item -LiteralPath "$SkinsPath..\CoreData\$SkinName" -Force -Recurse
    }

    Remove-Item -LiteralPath "$SkinsPath$SkinName" -Force -Recurse
    Remove-Item -LiteralPath "$SkinsPath@Backup\$SkinName" -Force -Recurse

    Remove-Section $SkinName
    # -- Rainmeter might not restart if the uninstalled skin is not loaded once! - #

    # Start-Sleep -s 1
    $RmAPI.Bang("[!WriteKeyvalue Variables Sec.variant `"Variants\Uninstalled.inc`"][!WriteKeyValue Variables Skin.Name $SkinName `"$($Resources)SecVar.inc`"][!WriteKeyValue Variables Skin.Set_Page Info `"$($Resources)SecVar.inc`"][`"$($Resources)Addons\RestartRainmeter.exe`"]")
}