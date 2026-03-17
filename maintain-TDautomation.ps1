<#
    .SYNOPSIS
    #TODO

    .DESCRIPTION
    #TODO

    .PARAMETER file
    Specifies an individual file, a glob spec or a root directory to be processed.

    .PARAMETER mode
    Specifies the processing required: Either 'dissect' or 'assemble'.
    Mode 'dissect' extracts provided file(s) into (a) structured, comparable filesystem(s) where the root directory of each filesystem is named equal to its source file.
    Mode 'assemble' compiles (a) serialized JSON file(s) by gathering all file contents in each provided filesystem identified by its root name.

    .PARAMETER output
    Optionally, the output file(s) in 'assemble' mode may be named differently from its (their) corresponding source root filesystem(s).

    .PARAMETER sparse
    When assembling, if set results in a non-compressed, i.e. whitespace preserved, JSON output file. By default, assemblies are compressed and thus less human readable.

    .INPUTS
    JSON serialized file(s) to dissect into (a) comparable, structured filesystem(s)

    .OUTPUTS
    JSON serialized file(s) assembled from (a) structuted filesystem(s)

    .EXAMPLE
    PS> <scriptname> -file "My TOPdesk automation export.json" -mode "dissect" -output "Directory to use as base for TOPdesk automation export"

    .EXAMPLE
    PS> <scriptname> -file "Directory used as base for TOPdesk automation assembly\My TOPdesk automation adjusted.json" -mode "assemble"

    .EXAMPLE
    PS> <scriptname> -file "Directory used as base for TOPdesk automation assembly" -mode "assemble" -sparse

    .NOTES
    Author: R.J. de Vries (Autom8ion@3Bdesign.nl)
    GitHub: WowBagger15/Autom8ion
            MEMF-IAM/TD-Factory
    Release notes:
        Version 1.2     : Changes to make comparing JSON output more consistent regardless of given source
        Version 1.0     : First operational version
        Version 0.9     : Init

#>

#region pragma
#requires -version 6
#endregion pragma

#region modules and namespaces
#endregion modules and namespaces

#region interface
[cmdletBinding()]
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
    [validateScript( { $mode -eq "assemble" } )]
    $output
    ,
    [validateScript( { $mode -eq "assemble" } )]
    [switch]
    $sparse
)
#endregion interface
#region begin block
begin {
    $__ = @{
        path          = split-path -parent -path $myInvocation.myCommand.definition
        name          = ( get-item $myInvocation.myCommand.definition ).baseName
        pid           = ( [System.Diagnostics.Process]::getCurrentProcess() ).id
        version       = '1.1.0'
        depth         = 10
        compress      = -not ( [bool]( $sparse) )
        indentation   = '    '
        identity      = '__stepIdentity'
        directive     = 'TDgarage'
    }
    function recurseTo-pipeline {
        <#
        .SYNOPSIS
            Recursively calls calling function feeding its pipeline rather than a parameter, which is removed from the bound parameter collection before invocation
            This is actually part of another module but generously incorporated here.
        .PARAMETER context
            The automatically created $PScmdLet variable from *within* the calling function itself
        .PARAMETER sending
            Name of the parameter that is being sent as pipeline input
        .PARAMETER feed
            Actual data fed into the pipeline
        .EXAMPLE
            function foo {
                param(
                    [parameter( valueFromPipeline )]
                    [object[]]
                    $main
                    ,
                    [int32]
                    $mode   = 42
                    ,
                    [switch]
                    $extra
                )
                process {
                    if ( -not $myInvocation.expectingInput ) {
                        return;
                    }
                    "Processing main item [{0}]" -f $_ | write-host;
                }
                end {
                    if ( -not $myInvocation.expectingInput ) {
                        recurseTo-pipeline $PScmdLet "main" $main;
                    }
                }
            }
        .NOTES
            TODO::Proper error handling
        #>
        [cmdletBinding()] 
        param(
            [parameter( mandatory, position = 0 )]
            [system.management.automation.PScmdlet]
            $context
            ,
            [parameter( mandatory, position = 1 )]
            [string]
            $sending
            ,
            [parameter( mandatory, position = 2 )]
            [object]
            $feed
        )
        try {
            # ! Must use the $PScmdLet.myInvocation chain here (in this case $context.myInvocation), and *not* directly $myInvocation
            [void]$context.myInvocation.boundParameters.remove( $sending );
            $_arguments = [hashTable]( $context.myInvocation.boundParameters );
            'Recursing pipeline to function [{0}] for parameter [{1}]' -f $context.MyInvocation.MyCommand.name, $sending | write-debug;
            $feed | & $context.myInvocation.myCommand @_arguments;
        } catch {}
    }
    function sort-objectEx {
        param(
            [parameter( valueFromPipeline )]
            [object]
            $object
            ,
            [int]
            $depth = 2
        )
        begin {
            if ( $depth -le 0 ) {
                '{0}: Maximum depth reached' -f ( get-PScallStack | select-object -first 1 -expand command ) | write-warning;
                return;
            }
        }
        process {
            if ( $object -is [hashTable] ) {
                $_export = [ordered]@{};
                $object.keys | sort-object |% {
                    if ( $object.$_ -is [array] ) {
                        $_export.$_ = @( ( $object.$_ | sort-objectEx -depth ( $depth - 1 ) ) );
                    } else {
                        $_export.$_ = $object.$_ | sort-objectEx -depth ( $depth - 1 );
                    }
                }
                return $_export;
            }
            if ( $object -is [array] ) {
                if ( $object.count ) {
                    return @( ( $object | sort-objectEx ( $depth - 1 ) ) );
                } else {
                    return @();
                }
            }
            return $object;
        }
    }
    function convertTo-JSONsorted {
        <#
        .SYNOPSIS
        Short description
        .DESCRIPTION
        Long description
        .EXAMPLE
        Example of how to use this cmdlet
        .EXAMPLE
        Another example of how to use this cmdlet
        .INPUTS
        Inputs to this cmdlet (if any)
        .OUTPUTS
        Output from this cmdlet (if any)
        .NOTES
        General notes
        .COMPONENT
        The component this cmdlet belongs to
        .ROLE
        The role this cmdlet belongs to
        .FUNCTIONALITY
        The functionality that best describes this cmdlet
        #>
        [cmdletBinding( positionalBinding )]
        [alias()]
        [outputType( [object] )]
        param (
            [parameter( mandatory, valueFromPipeline, position = 0 )]
            [object]
            $object
            ,
            [parameter( position = 1 )]
            [int]
            $depth = 2
            ,
            [switch]
            $AsArray
            ,
            [switch]
            $Compress
            ,
            [switch]
            $EnumsAsStrings
            ,
            [Newtonsoft.Json.StringEscapeHandling]
            $EscapeHandling
        )
        begin {
            [collections.arrayList]$_input = @();
            $_options = [hashTable]( $PScmdLet.myInvocation.boundParameters );
            if ( -not $_options.containsKey( "depth" ) ) {
                $_options.Depth = $depth;
            }
        }
        process {
            [void]$_input.add( ( $object | convertTo-Json -depth $depth | convertFrom-Json -asHashTable ) );
        }
        end {
            $_input | forEach-object <# -ThrottleLimit 5 #> {
                $_ | sort-objectEx -depth $depth
            } | convertTo-Json @_options;
        }
    }
    function get-source {
        <#
        .SYNOPSIS
        Reads source file(s) and converts it (them) into (a) custom object(s) using converFrom-JSON.

        .PARAMETER source
        One or more directories and/or files.
        #>
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
        <#
        .SYNOPSIS
        Re-creates a given file by removing it first (if pre-existing) and creating a new file node.
        This is used to create an empty stage on which to project object data in export-node.

        .PARAMETER path
        The literal file URI to use, either fully qualified or relative.
        #>
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
        <#
        .SYNOPSIS
        Compiles the name of a node directory in the steps or substeps structures of the automation.

        .DESCRIPTION

        Each step must be named uniquely and structured and reflect its order.
        It is paramount the directory containing the step data and the configuration of the step itself are comprised ot the same data.
        Therefore, each step directory's name is compiled into a FreeMarker source and stored, improperly but nonetheless,
        in a step's 'customExecutionCondition' property.

        .PARAMETER step
        The object containing the step information converted from the automation's JSON export.

        .PARAMETER name


        #>
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
                                ) | convertTo-JSONsorted -depth $__.depth | out-file -literalPath $_file;

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
                        $action | select-object $_.name | convertTo-JSONsorted -depth $__.depth | out-file -noNewLine -literalPath $_file;
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
            ,
            [hashtable]
            $info
        )
        $_info      = @{
            epoch   = [datetime]::now.toString()
        };
        if ( $info ) {
            $_info += $info;
        }
        $_file    = new-anchor -path $base;
        try {
            $_content = get-content -literalPath $_file -force -ea silentlyContinue | convertFrom-Json -ea silentlyContinue;
            if ( $null -eq $_content ) { throw }
        } catch {
            $_content = new-object PSobject;
        }
        $_content | add-member -memberType noteProperty -name $action -value $_info -force;
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
        # $_indentation   = [regex]::new( '^(?<indent>\s*)(?<line>.*)' );
        # $_size          = -1;
        if ( $_result   = import-node -base $base ) {
            $_export    = $_result | convertTo-JSONsorted -depth $__.depth -compress:$__.compress;
            $_info      = @{};
            [system.text.encoding]::UTF8.getBytes(
                ( $_export |% {
                    $_ -replace '^\s*', ''
                } )
            ) |? {
                $_ -notin 9, 32
            } | measure-object -sum |% {
                $_info.count  = [int64]$_.count;
                $_info.sum    = [int64]$_.sum;
                $_info.sparse = [bool]$sparse;
            }
            touch-anchor -base $base -action "assembled" -info $_info;
            $_export | out-file -literalPath $_target;
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
