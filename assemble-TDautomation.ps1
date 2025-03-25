#region pragma
#requires -version 6
#endregion pragma

param(
    [string]
    $root = "."
    ,
    [string[]]
    $name
    ,
    [string]
    $output
)
'Assembling json files in [{0}]' -f ( get-item -literalPath $root | select-object -expand fullName ) | write-host;
if ( $name ) {
    '  matching [{0}]' -f ( $name -join '] [' ) | write-host;
}
$_myPath = split-path -parent -path $myInvocation.myCommand.definition;
$_myTool = "maintain-TDautomation.ps1";
$_assembler = join-path -path $_myPath -childPath $_myTool;
'  Using assembler [{0}]' -f $_assembler | write-host;
if ( test-path -literalPath $_assembler -ea silentlyContinue ) {
    get-childItem -literalPath $root -directory |? {
        -not $name -or
        $_.baseName -in $name -or
        $_.name -in $name
    } |% {
        if ( get-childItem -literalPath $_.fullName -name ".TDaction" -force -ea silentlyContinue ) {
            $_target = '{0}.json' -f $_.fullName;
            '  Assembling [{0}] ...' -f $_target | write-host;
            if ( $output ) {
                $_output = @{
                    output = join-path -path $output -childPath ( split-path $_target -leaf );
                };
            } else {
                $_output = @{};
            }
            & $_assembler -file $_target -mode "assemble" @_output;
            '  Done.' | write-host;
        } else {
            '  Skipping directory [{0}]' -f $_.fullName | write-host;
        }
    }
} else {
    '  Unable to find assembler [{0}]' -f $_assembler | write-error;
}
'Done.' | write-host;
