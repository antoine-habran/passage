# Nushell completion for Passage.
# This file is licensed under the GPLv2+. See COPYING for details.

const commands = [ls find grep show insert edit generate reencrypt rm mv cp git help version]
const aliases = {
    list: ls, search: find, add: insert, delete: rm, remove: rm,
    rename: mv, copy: cp
}

def unquote [text: string] {
    if ($text | str starts-with '"') {
        return (try { $text | from nuon } catch { $'($text)"' | from nuon })
    }

    let quote = ($text | str substring 0..<1)
    if $quote in ["'" "`"] {
        let rest = ($text | str substring 1..)
        return (if ($rest | str ends-with $quote) { $rest | str substring ..<(-1) } else { $rest })
    }
    $text
}

def complete-entries [prefix: string, directories_only: bool = false, argument_prefix: string = ""] {
    let parts = ($prefix | split row "/")
    let parents = ($parts | drop 1)
    if (($prefix | str starts-with "/") or ($parts | any {|part| $part | str starts-with "." })) {
        return []
    }

    let root = ($env.PASSAGE_DIR? | default "" | if $in == "" { "~/.passage/store" } else { $in })
    let store = (try { $root | path expand --strict } catch { return [] })
    let directory = (try {
        [$store ...$parents] | path join | path expand --strict
    } catch { return [] })
    if not (try { $directory | path relative-to $store | ignore; true } catch { false }) {
        return []
    }

    let fragment = ($parts | last)
    let entries = (try { ls --short-names $directory | where {|entry| $entry.name | str starts-with $fragment } } catch { [] })
    $entries | each {|entry|
        let kind = if $entry.type != "symlink" {
            $entry.type
        } else {
            try {
                let target = ([$directory $entry.name] | path join | path expand --strict)
                $target | path relative-to $store | ignore
                $target | path type
            } catch { null }
        }
        let is_dir = ($kind == "dir")
        if $is_dir or (not $directories_only and $kind == "file" and ($entry.name | str ends-with ".age")) {
            let name = if $is_dir { $"($entry.name)/" } else { $entry.name | str replace --regex '\.age$' '' }
            let path = ($parents | append $name | str join "/")
            let argument = $"($argument_prefix)($path)"
            let value = if $argument =~ '^[[:alnum:]_./=-]+$' { $argument } else { $argument | to nuon }
            {value: $value, display_override: $argument, append_whitespace: (not $is_dir)}
        }
    } | sort-by display_override
}

def "nu-complete passage" [place: record, token: record] {
    let preceding = ($place.command | skip 1 | drop 1)
    let prefix = (try { unquote $token.text } catch { return [] })
    let first = (try { unquote ($preceding | get 0? | default "") } catch { "" })
    let command = ($aliases | get -o $first | default $first)
    let is_subcommand = ($command in $commands)
    let arguments = if $is_subcommand { $preceding | skip 1 } else { $preceding }
    let options = ("--" not-in $arguments)
    let mode = if $is_subcommand { $command } else { "show" }
    let flags = match $mode {
        show | ls => [-c --clip -q --qrcode]
        insert => [-e --echo -m --multiline -f --force]
        generate => [-n --no-symbols -c --clip -q --qrcode -i --in-place -f --force]
        rm => [-r --recursive -f --force]
        cp | mv => [-f --force]
        reencrypt => [-p --path]
        _ => []
    }

    if $mode == "reencrypt" and $options {
        if ($prefix | str starts-with "--path=") {
            return (complete-entries ($prefix | str substring 7..) true "--path=")
        }
        if (($arguments | last | default "") in [-p --path]) {
            return (complete-entries $prefix true)
        }
    }

    if $options and ($token.text | str starts-with "-") {
        let candidates = if ($preceding | is-empty) { $flags ++ [--help --version] } else { $flags }
        return ($candidates | where {|flag| $flag | str starts-with $prefix })
    }

    let max_args = match $mode {
        show | ls | insert | edit | generate | rm => 1
        cp | mv => 2
        _ => 0
    }
    let flags_end = if $options { $arguments | length } else {
        $arguments | enumerate | where {|item| $item.item == "--" } | get 0.index
    }
    let already_entered = (($arguments | take $flags_end | where {|arg| not ($arg | str starts-with "-") } | length)
        + (if $options { 0 } else { ($arguments | skip ($flags_end + 1) | length) }))
    let entries = if $already_entered < $max_args {
        complete-entries $prefix | where {|entry|
            not $options or not ($entry.display_override | str starts-with "-")
        }
    } else { [] }
    let names = if ($preceding | is-empty) {
        $commands | where {|name| $name | str starts-with $prefix } | each {|name| {value: $name, append_whitespace: true} }
    } else { [] }
    $names ++ $entries | uniq-by value
}

@complete "nu-complete passage"
export extern passage []
