function Add-CoreProtocol{
    $root = $RmAPI.VariableStr('CURRENTPATH') -replace '[^\\]+?\\$', ''
    Start-Process powershell -ArgumentList "& `"$root\Helpers\CoreInstaller\CoreInstallerWebSupport.ps1`" `"$root\Helpers\CoreInstaller\CoreInstaller.exe`" `"$root\WebSupport\WebSupportEnabled.txt`"" -Verb RunAs
}