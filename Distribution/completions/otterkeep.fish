function __otterkeep_should_offer_completions_for_flags_or_options -a expected_commands
    set -l non_repeating_flags_or_options $argv[2..]
    set -l non_repeating_flags_or_options_absent 0
    set -l positional_index 0
    set -l commands
    __otterkeep_parse_tokens
    test "$commands" = "$expected_commands"; and return $non_repeating_flags_or_options_absent
end

function __otterkeep_should_offer_completions_for_positional -a expected_commands positional_index_comparison expected_positional_index
    set -l non_repeating_flags_or_options
    set -l non_repeating_flags_or_options_absent 0
    set -l positional_index 0
    set -l commands
    __otterkeep_parse_tokens
    test "$commands" = "$expected_commands" -a \( "$positional_index" "$positional_index_comparison" "$expected_positional_index" \)
end

function __otterkeep_parse_tokens -S
    set -l unparsed_tokens (__otterkeep_tokens -pc)
    switch $unparsed_tokens[1]
    case 'otterkeep'
        __otterkeep_parse_subcommand 0 'lang=' 'debug' 'version' 'h/help'
        switch $unparsed_tokens[1]
        case 'backup'
            __otterkeep_parse_subcommand 1 'profile=' 'dry-run' 'full' 'continuous' 'version' 'h/help'
        case 'restore'
            __otterkeep_parse_subcommand 1 'profile=' 'snapshot=' 'file=' 'target=' 'collision=' 'version' 'h/help'
        case 'restore-snapshot'
            __otterkeep_parse_subcommand 1 'profile=' 'snapshot=' 'target=' 'collision=' 'version' 'h/help'
        case 'profile'
            __otterkeep_parse_subcommand 0 'version' 'h/help'
            switch $unparsed_tokens[1]
            case 'list'
                __otterkeep_parse_subcommand 0 'version' 'h/help'
            case 'show'
                __otterkeep_parse_subcommand 1 'version' 'h/help'
            case 'create'
                __otterkeep_parse_subcommand 0 'name=' 'source=' 'destination=' 'version' 'h/help'
            case 'delete'
                __otterkeep_parse_subcommand 1 'version' 'h/help'
            end
        case 'schedule'
            __otterkeep_parse_subcommand 0 'version' 'h/help'
            switch $unparsed_tokens[1]
            case 'check'
                __otterkeep_parse_subcommand 0 'version' 'h/help'
            case 'run'
                __otterkeep_parse_subcommand 0 'version' 'h/help'
            end
        case 'diagnostics'
            __otterkeep_parse_subcommand 0 'version' 'h/help'
            switch $unparsed_tokens[1]
            case 'bundle'
                __otterkeep_parse_subcommand 0 'output=' 'version' 'h/help'
            end
        case 'status'
            __otterkeep_parse_subcommand 0 'version' 'h/help'
        case 'replicate'
            __otterkeep_parse_subcommand 0 'profile=' 'snapshot=' 'version' 'h/help'
        case 'photos'
            __otterkeep_parse_subcommand 1 'version' 'h/help'
        case 'prune'
            __otterkeep_parse_subcommand 0 'profile=' 'keep=' 'version' 'h/help'
        case 'daemon'
            __otterkeep_parse_subcommand 1 'version' 'h/help'
        case 'doctor'
            __otterkeep_parse_subcommand 0 'version' 'h/help'
        case 'snapshots'
            __otterkeep_parse_subcommand 1 'profile=' 'version' 'h/help'
        case 'file-history'
            __otterkeep_parse_subcommand 1 'gui' 'version' 'h/help'
        case 'logs'
            __otterkeep_parse_subcommand 0 'path' 'list' 'enable' 'disable' 'limit=' 'version' 'h/help'
        case 'scrub'
            __otterkeep_parse_subcommand 0 'profile=' 'limit=' 'version' 'h/help'
        case 'diff'
            __otterkeep_parse_subcommand 0 'profile=' 'target=' 'base=' 'file=' 'side-by-side' 'version' 'h/help'
        case 'lock'
            __otterkeep_parse_subcommand 0 'snapshot=' 'profile=' 'days=' 'version' 'h/help'
        case 'unlock'
            __otterkeep_parse_subcommand 0 'snapshot=' 'profile=' 'version' 'h/help'
        case 'help'
            __otterkeep_parse_subcommand -r 1 'version'
        end
    end
end

function __otterkeep_tokens
    if test (string split -m 1 -f 1 -- . "$FISH_VERSION") -gt 3
        commandline --tokens-raw $argv
    else
        commandline -o $argv
    end
end

function __otterkeep_parse_subcommand -S -a positional_count
    argparse -s r -- $argv
    set -l option_specs $argv[2..]
    set -l is_repeating_positional $_flag_r
    set -el _flag_r
    set -a commands $unparsed_tokens[1]
    set positional_index 0
    while true
        set -e unparsed_tokens[1]
        argparse -sn "$commands" $option_specs -- $unparsed_tokens 2> /dev/null
        set unparsed_tokens $argv
        set positional_index (math $positional_index + 1)
        for non_repeating_flag_or_option in $non_repeating_flags_or_options
            if set -ql "_flag_$(string replace -a - _ -- $non_repeating_flag_or_option)"
                set non_repeating_flags_or_options_absent 1
                break
            end
        end
        test (count $unparsed_tokens) -eq 0 -o \( -z "$is_repeating_positional" -a "$positional_index" -gt "$positional_count" \) && break
    end
end

function __otterkeep_complete_directories
    set -l token (commandline -t)
    string match -- '*/' $token
    set -l subdirs $token*/
    printf %s\n $subdirs
end

function __otterkeep_custom_completion
    set -x SAP_SHELL fish
    set -x SAP_SHELL_VERSION $FISH_VERSION
    set -l tokens (__otterkeep_tokens -p)
    if test -z "$(__otterkeep_tokens -t)"
        set -l index (count (__otterkeep_tokens -pc))
        set tokens $tokens[..$index] \'\' $tokens[(math $index + 1)..]
    end
    command $tokens[1] $argv $tokens
end

complete -c 'otterkeep' -f
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep" lang' -l 'lang' -d 'Application language: en or hu' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep" debug' -l 'debug' -d 'Enable verbose debug file logging to ~/Library/Logs/OtterKeep/'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'backup' -d 'Execute a backup session or pre-backup simulation.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'restore' -d 'Restore individual files or folders from a historical snapshot.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'restore-snapshot' -d 'Restore an entire snapshot hierarchy atomically.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'profile' -d 'Manage backup profiles (list, show, create, delete).'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'schedule' -d 'Evaluate schedules and trigger due backups.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'diagnostics' -d 'Generate system diagnostic reports and bundles.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'status' -d 'Display status of all backup profiles.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'replicate' -d 'Trigger 3-2-1 secondary replication (Backup Copy Job).'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'photos' -d 'Manage Apple Photos sanctuary backups.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'prune' -d 'Prune obsolete historical snapshots.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'daemon' -d 'Manage headless background daemon.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'doctor' -d 'Run system diagnostics and check permissions.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'snapshots' -d 'List recorded snapshots in the catalog.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'file-history' -d 'Inspect historical versions of a file across snapshots.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'logs' -d 'Inspect unified diagnostic logs.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'scrub' -d 'Run cryptographic SHA-256 data scrubbing pass.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'diff' -d 'Compare snapshots or file contents.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'lock' -d 'Apply WORM immutability protection to a snapshot.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'unlock' -d 'Remove user immutable flag from a snapshot.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep" -eq 1' -fa 'help' -d 'Show subcommand help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" profile' -l 'profile' -d 'Target backup profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" dry-run' -l 'dry-run' -d 'Perform non-destructive dry-run analysis'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" full' -l 'full' -d 'Force full baseline backup without CoW cloning'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" continuous' -l 'continuous' -d 'Run in continuous event-driven mode (FSEvents)'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep backup" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" profile' -l 'profile' -d 'Target backup profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" snapshot' -l 'snapshot' -d 'Snapshot identifier to restore from' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" file' -l 'file' -d 'Relative path of file inside snapshot root' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" target' -l 'target' -d 'Destination path where item will be restored' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" collision' -l 'collision' -d 'Collision resolution strategy (keepBoth, overwrite, skip)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" profile' -l 'profile' -d 'Target backup profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" snapshot' -l 'snapshot' -d 'Snapshot identifier to restore' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" target' -l 'target' -d 'Target destination directory' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" collision' -l 'collision' -d 'Collision resolution strategy (overwrite, keepBoth, skip)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep restore-snapshot" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep profile" -eq 1' -fa 'list' -d 'List all configured profiles.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep profile" -eq 1' -fa 'show' -d 'Show detailed profile configuration.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep profile" -eq 1' -fa 'create' -d 'Create a new backup profile.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep profile" -eq 1' -fa 'delete' -d 'Delete an existing backup profile.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile list" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile list" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile show" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile show" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile create" name' -l 'name' -d 'Profile name' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile create" source' -l 'source' -d 'Source folder path' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile create" destination' -l 'destination' -d 'Destination folder path' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile create" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile create" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile delete" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep profile delete" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep schedule" -eq 1' -fa 'check' -d 'Check for overdue scheduled backups.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep schedule" -eq 1' -fa 'run' -d 'Run scheduled backup checks immediately.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule check" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule check" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule run" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep schedule run" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diagnostics" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diagnostics" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_positional "otterkeep diagnostics" -eq 1' -fa 'bundle' -d 'Export sanitized diagnostic support bundle.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diagnostics bundle" output' -l 'output' -d 'Target output path for zip archive' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diagnostics bundle" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diagnostics bundle" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep status" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep status" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep replicate" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep replicate" snapshot' -l 'snapshot' -d 'Target snapshot ID to replicate (defaults to latest)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep replicate" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep replicate" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep photos" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep photos" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep prune" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep prune" keep' -l 'keep' -d 'Number of newest snapshots to retain' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep prune" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep prune" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep daemon" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep daemon" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep doctor" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep doctor" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep snapshots" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep snapshots" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep snapshots" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep file-history" gui' -l 'gui' -d 'Open version history in macOS graphical interface'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep file-history" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep file-history" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" path' -l 'path' -d 'Print active log file path'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" list' -l 'list' -d 'List all recorded log files'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" enable' -l 'enable' -d 'Enable debug file logging'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" disable' -l 'disable' -d 'Disable debug file logging'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" limit' -l 'limit' -d 'Number of log lines to show' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep logs" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep scrub" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep scrub" limit' -l 'limit' -d 'Limit count of recent snapshots to scrub' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep scrub" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep scrub" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" target' -l 'target' -d 'Target snapshot ID (default: latest)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" base' -l 'base' -d 'Base snapshot ID (default: previous)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" file' -l 'file' -d 'Relative path of file to compare' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" side-by-side' -l 'side-by-side' -d 'Render aligned side-by-side Myers LCS line comparison'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep diff" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep lock" snapshot' -l 'snapshot' -d 'Snapshot identifier to lock' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep lock" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep lock" days' -l 'days' -d 'Lock retention period in days (default: 30)' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep lock" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep lock" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep unlock" snapshot' -l 'snapshot' -d 'Snapshot identifier to unlock' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep unlock" profile' -l 'profile' -d 'Target profile name or UUID' -rfka ''
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep unlock" version' -l 'version' -d 'Show the version.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep unlock" h help' -s 'h' -l 'help' -d 'Show help information.'
complete -c 'otterkeep' -n '__otterkeep_should_offer_completions_for_flags_or_options "otterkeep help" version' -l 'version' -d 'Show the version.'
