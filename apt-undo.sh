#!/bin/bash

# Walk backwards through "^Install: " lines in apt log and show
# numbered summaries of installed packages per action. With "-iN" show
# a full list of installed packages for the line N. Add "-q" to
# suppress "Total packages to remove: .." message. The message is
# written to stderr so it doesnt corrupt the package list anyways.
#
# Example: get list of packages to undo last apt install
#
#     apt-undo.sh -i1
#

bye () {
    echo $@ >&2
    exit 1
}

usage () {
    grep . <<EOF
${0##*/} [-iN] [-q] [-f <path>] [-h]

>> use -iN to pick index N quick

>> use -f <path> to supply custom log. '-' states for stdin

>> use -q to suppress number of packages to remove so along with -iN
only packages to remove are dumped

EOF

}

is_int () {
    test "$1" -eq "$1" 2>/dev/null
}

log_lines () {
    tac "$1" |\
        grep -oP '(?<=^Install: ).+' |\
        sed -r 's/\([^)]+\)//g;s/ *, */ /g'
}

narg () {
    echo $#
}

make_hint () {
    local l=68 total=$#
    local -a hint

    while [[ $# -gt 0 ]]; do
        ((l -= ${#1} + 1))

        if [[ $l -lt 0 ]]; then
            hint+=("+$(( $total - ${#hint[@]} ))")
            break
        fi

        hint+=($1)
        shift
    done

    echo ${hint[@]}
}

main () {
    local arg quiet index=0 log=/var/log/apt/history.log

    # termux
    if [[ -n $PREFIX ]]; then
        log="$PREFIX"$log
    fi

    while getopts ':i:f:qh' arg; do
        case $arg in
            i)
                index=$OPTARG
                if ! is_int "$index" || [[ $index -lt 1 ]]; then
                    bye -i value must be natural
                fi
                ;;
            f)
                log=$OPTARG

                if [[ -z $log ]]; then
                    bye Empty -f value
                fi

                if [[ $log != - ]]; then
                    local t=$(readlink -e "$log")

                    if [[ -z $t ]]; then
                        bye File not available: "$log"
                    fi

                    if [[ ! -f $t || ! -r $t ]]; then
                        bye Not a readable file: "$log"
                    fi

                    unset t
                fi
                ;;
            q)
                quiet=y
                ;;
            h)
                usage
                exit
                ;;
            :)
                bye Option requires value: -$OPTARG
                ;;
            \?)
                bye Unknown option: -$OPTARG
                ;;
        esac
    done

    log_lines "$log" | {
        if [[ $index -gt 0 ]]; then
            line=$(sed -n ${index}p)

            if [[ -z $line ]]; then
                bye -i value is too big
                exit
            fi

            if [[ -z $quiet ]]; then
                echo Total packages to remove: $(narg $line) >&2
            fi

            echo $line
        else
            n=0

            while read line; do
                printf "%-4d" $((++n))
                make_hint $line
            done
        fi
    }
}

main "$@"
