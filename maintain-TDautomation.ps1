#region pragma
#requires -version 6
#endregion pragma

[cmdLetBinding()]
param(
    [parameter( mandatory, valueFromPipeline )]
    $file
    ,
    [validateSet(
            "dissect"
        ,   "assemble"
    )]
    [string]
    $mode = "dissect"
    ,
    [parameter()]
    [validateScript( { $mode -eq "assemble" } )]
    $output
)
begin {
    $__ = @{
        path          = split-path -parent -path $myInvocation.myCommand.definition
        name          = ( get-item $myInvocation.myCommand.definition ).baseName
        pid           = ( [System.Diagnostics.Process]::getCurrentProcess() ).id
        version       = '0.3.0'
        depth         = 10
        indentation   = '    '
        identity      = '__stepIdentity'
        directive     = 'TDgarage'
    }
    function get-source {
        param(
            $source
        )
        if ( $source -is [system.IO.fileInfo] ) {
            $_source = $source.fullName;
        } else {
            $_source = $source;
        }
        if ( -not $_source.contains( [system.io.path]::directorySeparatorChar ) ) {
            $_source = join-path -path $__.path -childPath $_source;
        }
        if ( test-path -literalPath $_source ) {
            get-content -literalPath $_source | convertFrom-Json -depth $__.depth;
        }
    }
    function get-target {
        param(
            $source
            ,
            [switch]
            $force
        )
        if ( $source -is [system.IO.fileInfo] ) {
            $_source = $source.fullName;
        } else {
            $_source = $source;
        }
        if ( -not $_source.contains( [system.io.path]::directorySeparatorChar ) ) {
            $_source = join-path -path $__.path -childPath $_source;
        }
        if ( -not ( $_target = get-item -literalPath $_source -ea silentlyContinue ) ) {
            if ( -not ( $_target = new-item -path $_source -ea silentlyContinue ) ) {
                # given target not found nor creatable
                return;
            }
        }
        if ( $_target -is [system.IO.directoryInfo] ) {
            if ( test-path -literalPath ( new-anchor -path $_target.fullName ) ) {
                return $_target.fullName;
            } else {
                # no anchor found
            }
        } else {
            $_target = join-path -path $_target.directory.fullName -childPath $_target.baseName;
            if ( $force ) {
                return $_target;
            }
            if ( $_target = get-item -literalPath $_target -ea silentlyContinue ) {
                if ( test-path -literalPath ( new-anchor -path $_target.fullName ) ) {
                    return $_target.fullName;
                } else {
                    # no anchor found
                }
            } else {
                # given directory does not exist
            }
        }
    }
    function stage-node {
        param(
            $path
        )
        try {
            if ( test-path -literalPath $path -ea silentlyContinue ) {
                [void]( remove-item -literalPath $path -recurse -force );
            }
            [void]( new-item -itemType directory -path $path );
            return $true;
        } catch {
            return $false;
        }
    }
    function set-stepName {
        param(
            $step
            ,
            $name
        )
    #   if ( $name -eq ( get-stepName -step $step -index -1 ) ) {
    #       return;
    #   }
        $_content = $step."customExecutionCondition";
        if ( $_content -match $__.identity ) {
            $_content = $_content -replace ( '<#assign [^>]*{0}[^>]+>\n*' -f $__.identity ), '';
        }
        if ( $_content -match $__.directive ) {
            $_content = $_content -replace ( '<#--{0}::"[^"]+"-->\n*' -f $__.directive ), '';
        }
        if ( -not $_content.trim() ) {
            $_content = 'true';
        }
        $step."customExecutionCondition" = @(
        #   '<#assign {0} = "{1}" />' -f $__.identity, $name
            '<#--{0}::"{1}"-->' -f $__.directive, $name
            $_content
        ) -join '';
    }
    function get-stepName {
        param( $step, $index )
        if ( $step."customExecutionCondition" -match $__.identity ) {
            return [string]( [regex]::new( ( '{0}[\s="]+(?<identity>[^"]+)' -f $__.identity ) ).match( $step."customExecutionCondition" ).groups["identity"].value );
        }
        if ( $step."customExecutionCondition" -match $__.directive ) {
            return [string]( [regex]::new( ( '<#--{0}::"(?<identity>[^"]+)' -f $__.directive ) ).match( $step."customExecutionCondition" ).groups["identity"].value );
        }
        $_ordinal = '{0:D3}' -f ( ( $index + 1 ) * 10 );
        $_name = switch( $step."type" ) {
            "ASSIGN_VARIABLE" {
                @(
                    $_ordinal
                    $step."type"
                    $step."assignmentType"
                    $step."variableKey"
                );
                break;
            }
            "HTTP_REQUEST" {
                @(
                    $_ordinal
                    $step."type"
                    $step."method"
                    $step."name"
                );
                break;
            }
            default {
                @(
                    $_ordinal
                    $step."type"
                );
            }
        }
        return [string]( $_name -join ' - ' );
    }
    function export-node {
        param(
            $base
            ,
            $action
            ,
            $root = ""
            ,
            [switch]
            $linger
        )
        $_base = join-path $base $root;
        if ( $linger -or ( stage-node -path $_base ) ) {
            $action.PSobject.properties |% {
                $_base = join-path $base $root;
                $_done = $false;
                $_root = @(
                    $root
                    $_.name
                ) -join "/";
                $_file = join-path -path $_base -childPath ( $_.name, "json" -join "." )
                $_asObject = $false;
                if ( $_root -eq "/action/configuration/steps" -or $_root -like "/action/configuration/steps/*/subSteps" ) {
                    $_base = join-path -path $_base -childPath $_.name;
                    if ( stage-node -path $_base ) {
                        $_steps = $_.value;
                        for( $_caret = 0; $_caret -lt $_steps.count; $_caret++ ) {
                            $_step = $_steps[ $_caret ];
                            $_stepName = get-stepName -step $_step -index $_caret;
                            $_dir = join-path -path $_base -childPath $_stepName;
                            if ( stage-node -path $_dir ) {

                                $_file = join-path -path $_dir -childPath "__step.json";

                                $_step."executionCondition" = switch( $_step."executionCondition" ){
                                    "ALWAYS" {
                                        "CUSTOM";
                                        break;
                                    }
                                    "ONLY_WHEN_PREVIOUS_SUCCEEDED" {
                                        "ONLY_WHEN_PREVIOUS_SUCCEEDED_AND_CUSTOM";
                                        break;
                                    }
                                    default {
                                        $_step."executionCondition";
                                        break;
                                    }
                                }
                                set-stepName -step $_step -name $_stepName;

                                $_step | select-object -property (
                                    $_step.PSobject.properties.name |? {
                                        $_ -notIn "url", "valueTemplate", "body", "subSteps"
                                    }
                                ) | convertTo-Json -depth $__.depth | out-file -literalPath $_file;

                                "url", "valueTemplate", "body" |% {
                                    if ( [bool]( $_step.PSobject.properties.match( $_ ).name ) ) {
                                        $_file = join-path -path $_dir -childPath ( $_, "ftl" -join "." );
                                        $_step.PSobject.properties.match( $_ ).value | out-file -literalPath $_file;
                                    }
                                }

                                if ( [bool]( $_step.PSobject.properties.match( "subSteps").name ) ) {
                                    $_subRoot = @(
                                        $_root
                                        $_stepName
                                    ) -join "/";
                                    export-node -base $base -action ( $_step | select-object -property "subSteps" ) -root $_subRoot -linger;
                                }

                            } else {
                                throw( ( "Unable to stage directory [{0}]" -f $_dir ) );
                            }
                        }
                    }
                    $_done = $true;
                } elseif ( $_root -eq "/action/description" ) {
                    $_file = join-path -path $_base -childPath ( $_.name, "txt" -join "." )
                    $action | select-object -expand "description" | out-file -noNewLine -literalPath $_file;
                    $_done = $true;
                } elseif ( $_root -eq "/action/configuration/variables" ) {
                    $_asObject = $true;
                }
                if ( -not $_done ) {
                    if ( $_asObject -or -not ( $_.value -is [PSobject] ) ) {
                        $action | select-object $_.name | convertTo-Json -depth $__.depth | out-file -noNewLine -literalPath $_file;
                    } else {
                        export-node -base $base -action $_.value -root $_root;
                    }
                }
            }
        } else {
            throw( "Unable to stage directory [{0}]" -f $_base );
        }
    }
    function new-anchor {
        param(
            $path
        )
        join-path -path $path -childPath ".TDaction";
    }
    function touch-anchor {
        param(
            [parameter( mandatory )]
            [string]
            $base
            ,
            [validateSet( "assembled", "dissected" )]
            [string]
            $action
        )
        $_epoch   = [datetime]::now.toString();
        $_file    = new-anchor -path $base;
        try {
            $_content = get-content -literalPath $_file -force -ea silentlyContinue | convertFrom-Json -ea silentlyContinue;
            if ( $null -eq $_content ) { throw }
        } catch {
            $_content = new-object PSobject;
        }
        if ( $_content.$action ) {
            $_content.$action = $_epoch;
        } else {
            $_content | add-member -memberType noteProperty -name $action -value $_epoch;
        }
        $_content | convertTo-Json | set-content -literalPath $_file -force;
    }
    function dissect-action {
        param(
            $base
            ,
            $action
        )
        try {
            export-node -base $base -action $action
        <#
            [datetime]::now.toString() | set-content -literalPath ( new-anchor -path $base ) -force;
        #>
            touch-anchor -base $base -action "dissected";
        } catch {
            $_.exception.message | write-error;
        }
    }
    function probe-node {
        param(
            $path
        )
        try {
            if ( test-path -literalPath $path -ea silentlyContinue ) {
                get-item -literalPath $path -force;
            }
        } catch {}
    }
    function import-node {
        param(
            $base
            ,
            $root = ""
        )
        $_target = new-object PSobject;
        $_base = join-path $base $root;
        if ( $_node = probe-node -path $_base ) {
            get-childItem -literalPath $_node -file |? {
                $_.baseName
            } |% {
                $_object = $null;
                if ( $_.extension -eq ".json" ) {
                    $_object = $_ | get-content | convertFrom-Json -depth $__.depth;
                } elseif ( $_.extension -eq ".ftl" ) {
                    $_object = new-object PSobject -property @{ $_.baseName = ( $_ | get-content ) };
                } elseif ( $_.extension -eq ".txt" ) {
                    $_object = new-object PSobject -property @{ $_.baseName = ( $_ | get-content -raw ) };
                }
                if ( $_object.PSobject.properties.match( $_.baseName ).name ) {
                    $_target | add-member -memberType noteProperty -name $_.baseName -value $_object.( $_.baseName );
                }
            }
            get-childItem -literalPath $_node -directory |% {
                $_root = @(
                    $root
                    $_.baseName
                ) -join "/";
                $_object = $null;
                if ( $_root -eq "/action/configuration/steps" -or $_root -eq "/subSteps" ) {
                    $_object = @();
                    $_base = join-path -path $_node -childPath $_.baseName;
                    $_caret = 0;
                    get-childItem -literalPath $_base -directory | sort-object baseName |% {
                        $_dir = join-path -path $_base -childPath $_.baseName;
                        get-childItem -literalPath $_dir -file -include "*.json" |% {
                            $_step = $_ | get-content | convertFrom-Json -depth $__.depth;
                            set-stepName -step $_step -name ( get-stepName -step $_step -index $_caret );
                        }
                        get-childItem -literalPath $_dir -file -include "*.ftl" |% {
                            $_content = ( $_ | get-content ) -join "`n";
                            $_step | add-member -memberType noteProperty -name $_.baseName -value $_content;
                        }
                        get-childItem -literalPath $_dir -directory -include "subSteps" |% {
                            $_step | add-member -memberType noteProperty -name $_.baseName -value ( import-node -base $_dir ).( $_.baseName );
                        }
                        $_object += $_step;
                        $_caret++;
                    }
                } else {
                    $_object = import-node -base $base -root $_root;
                }
                $_target | add-member -memberType noteProperty -name $_.baseName -value $_object;
            }
        }
        $_target;
    }
    function assemble-action {
        param(
            $base
            ,
            $target
        )
        if ( $target -is [string] ) {
            if ( $target.endsWith( ".json" ) ) {
                $_target = $target;
            } else {
                $_target      = @(
                    $target
                    "json"
                ) -join ".";
            }
        } else {
            $_target = $target.fullName;
        }
        $_indentation = [regex]::new( '^(?<indent>\s*)(?<line>.*)' );
        $_size        = -1;
        if ( $_result = import-node -base $base ) {
        <#
            $_assembled = [datetime]::now.toString();
            $_assembled | set-content -literalPath ( new-anchor -path $base ) -force;
            if ( $_result."assembled" ) {
                $_result."assembled" = $_assembled;
            } else {
                $_result | add-member -memberType noteProperty -name "assembled" -value $_assembled;
            }
        #>
            touch-anchor -base $base -action "assembled";
            ( $_result | convertTo-Json -depth $__.depth ) -split "[`r`n]+" |% {
                if ( $_indented = $_indentation.match( $_ ) ) {
                    if ( $_size -lt 0 -and $_indented.groups["indent"].length -gt 0 ) {
                        $_size = $_indented.groups["indent"].length;
                    }
                    @(
                        $__.indentation * ( $_indented.groups["indent"].length / ( [math]::abs( $_size ) ) )
                        $_indented.groups["line"].value
                    ) -join '';
                } else {
                    $_;
                }
            } | out-file -literalPath $_target;
        }
    }
}

process {
    if ( $input ) {
        $file = $input;
    }

    if ( $mode -eq "dissect" ) {
        if ( $_base = get-target -source $file -force ) {
            if ( $_action = get-source -source $file ) {
                dissect-action -base $_base -action $_action;
            }
        }
    }

    if ( $mode -eq "assemble" ) {
        if ( $_base = get-target -source $file ) {
            if ( $output ) {
                assemble-action -base $_base -target $output;
            } else {
                assemble-action -base $_base -target $file;
            }
        }
    }

}
