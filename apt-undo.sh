#!/bin/bash

# Walk backwards through "^Install: " lines in apt log, or "^Upgrade: "
# if the "-d" (downgrade) option is given, and show numbered summaries
# of installed packages per action. With "-iN" show a full list of
# installed packages for the line N. Add "-q" to suppress total number
# of packages message. The message is written to stderr so it doesnt
# corrupt the package list anyways.
#
# Example: get list of packages to remove to undo last apt install
#
#     apt-undo.sh -i1
#

bye () {
    echo $@ >&2
    exit 1
}

usage () {
    cat <<EOF
${0##*/} [-iN] [-q] [-zN | -f <path>] [-d] [-h]

>> use -iN to show full list of packages for line N
>> use -f <path> to supply custom log. '-' states for stdin
>> use -zN to operate on N'th rotated log in default location
>> use -q with -iN to suppress total number of packages message
>> use -d (downgrade) to process upgraded packages

-z and -f are mutually exclusive.

EOF

}

is_int () {
    test "$1" -eq "$1" 2>/dev/null
}

is_natural () {
    is_int "$1" && [[ $1 -gt 0 ]]
}

smart_zcat() {
    local cmd=cat

    if [[ $1 == *.gz ]]; then
        cmd=zcat
    fi

    $cmd "$1"
}

log_lines () {
    if [[ ${1:-install} == install ]]; then
        # packages to remove
        tac |\
            grep -oP '(?<=^Install: ).+' |\
            sed -r 's/\([^)]+\)//g;s/ *, */ /g'
    else
        # packages to downgrade
        tac |\
            grep -oP '(?<=^Upgrade: ).+' |\
            awk -F '), *' '{ for ( i=1; i<=NF; i++ ) {
                                split( $i, a, /[ ,(]+/ )
                                printf( "%s=%s ", a[1], a[2] )
                             }
                             print ""
                           }'
    fi
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
    local quiet index=0 prefix=/var/log/apt lookfor=install

    # termux
    if [[ -n $PREFIX ]]; then
        prefix="$PREFIX"$prefix
    fi

    local log=$prefix/history.log

    local arg opt_set=
    while getopts ':i:z:f:qhd' arg; do
        opt_set=${opt_set}$arg

        if [[ $opt_set == *z* && $opt_set == *f* ]]; then
            bye -z and -f are mutually exclusive
        fi

        case $arg in
            i)
                index=$OPTARG
                if ! is_natural "$index"; then
                    bye -i value must be natural
                fi
                ;;
            z)
                local t=$OPTARG
                if ! is_natural "$t"; then
                    bye -z value must be natural
                fi

                log=$prefix/history.log.$t.gz

                if [[ ! -f $log ]]; then
                    bye Rotated log \#$t doesnt exist
                fi

                unset t
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
            d)
                lookfor=downgrade
                ;;
            :)
                bye Option requires value: -$OPTARG
                ;;
            \?)
                bye Unknown option: -$OPTARG
                ;;
        esac
    done

    unset arg opt_set

    smart_zcat "$log" | log_lines $lookfor | {
        if [[ $index -gt 0 ]]; then
            line=$(sed -n ${index}p)

            if [[ -z $line ]]; then
                bye -i value is too big
                exit
            fi

            if [[ -z $quiet ]]; then
                echo Total number of packages: $(narg $line) >&2
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
