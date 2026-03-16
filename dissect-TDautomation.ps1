#region pragma
#requires -version 6
#endregion pragma

param(
    [string]
    $root = "."
    ,
    [string[]]
    $name
)
'Dissecting json files in [{0}]' -f ( get-item $root | select-object -expand fullName ) | write-host;
if ( $name ) {
    '  matching [{0}]' -f ( $name -join '] [' ) | write-host;
}
$_myPath = split-path -parent -path $myInvocation.myCommand.definition;
$_myTool = "maintain-TDautomation.ps1";
$_dissector = join-path -path $_myPath -childPath $_myTool;
'  Using dissector [{0}]' -f $_dissector | write-host;
if ( test-path -literalPath $_dissector -ea silentlyContinue ) {
    get-childItem -literalPath $root -include "*.json" |? {
        -not $name -or
        $_.baseName -in $name -or
        $_.name -in $name
    } |% {
        '  Dissecting [{0}] ...' -f $_.fullName | write-host;
        & $_dissector -file $_ -mode "dissect";
        '  Done.' | write-host;
    }
} else {
    '  Unable to find dissector [{0}]' -f $_dissector | write-error;
}
'Done.' | write-host;
