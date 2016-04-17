#!/bin/bash
# merge CNC scripts (ngc files) so that first all Schruppen is done and then all Schlichten is done

readonly PROGNAME=$(basename "$0")
readonly PROGDIR=$(dirname "$(readlink -m "$0")")
readonly -a ARGS=("$@")

printUsage() {
    cat <<EOF
usage: $PROGNAME <ngc_files>...
EOF
}

# Always use declare instead of local!
# It's more general, can do more, and leads to more consistency.

readonly TEMPDIR=$(mktemp -d tmp.XXXXXXXXXX)
function finish {
    rm -rf "$TEMPDIR"
}
trap finish EXIT

# $1: error message
exitWithError() {
    echo "$1" >&2
    exit 1
}

# comment line; must NOT contain any special characters, see usage in grep and awk!
readonly THIS_COMMENT_LINE='Arbeitsgang Schlichten'

readonly BEFEHL_SPINDEL_AUS='M05'
readonly BEFEHL_PROGRAMM_ENDE='M30'

# $1: Gradzahl für Drehbefehl (oder besser Schwenkbefehl?)
befehlDrehen() {
    declare gradzahl="$1"
    echo "G0 A$gradzahl"
}

befehlDrehenAusgangsposition() {
    befehlDrehen 0
}

befehlProgrammPause() {
    echo 'M0'
}

befehlProgrammEnde() {
    echo "$BEFEHL_PROGRAMM_ENDE"
}

befehlSpindelAus() {
    echo "$BEFEHL_SPINDEL_AUS"
}

# $1: comment (without parenthesis)
outputNgcComment() {
    declare comment
    comment=$(echo "$1" | tr '()' '..')
    echo "($comment)"
}

# $1: input ngc file
checkInputFile() {
    # file exist, is regular file, and read permission is granted
    [[ -f $i && -r $i ]] \
        || exitWithError "error: CNC script file does not exist or cannot be read: $i"

    # this comment line exist one single time in the file
    declare n
    n=$(grep -c "$THIS_COMMENT_LINE" "$i")
    [[ $n == 1 ]] \
        || exitWithError "error: '$THIS_COMMENT_LINE' appears $n times in the CNC script file but must appear exactly one time: $i"
}

# $1: input ngc file
outputFirstPart() {
    awk "/$THIS_COMMENT_LINE/{exit}; 1" "$1"
}

# $1: input ngc file
outputSecondPart() {
    awk "start; /$THIS_COMMENT_LINE/{start=1}" "$1"
}

# Remove unwanted CNC commands
removeUnwantedCommands() {
    grep -vE "^(${BEFEHL_SPINDEL_AUS}|${BEFEHL_PROGRAMM_ENDE})\b"
}

main() {
    [[ ${#ARGS} == 0 ]] && { printUsage; exit; }

    declare filePart1="$TEMPDIR/part1.txt"
    declare filePart2="$TEMPDIR/part2.txt"
    # make sure files are empty:
    > "$filePart1"
    > "$filePart2"

    declare absoluteDegrees=0

    for i in "${ARGS[@]}"; do

        checkInputFile "$i"

        (( absoluteDegrees += 90 ))

        {
            outputNgcComment "## $i"
            outputFirstPart "$i"
            befehlDrehen "$absoluteDegrees"
            befehlProgrammPause
        } >> "$filePart1"

        {
            outputNgcComment "## $i"
            outputSecondPart "$i" | removeUnwantedCommands
            befehlDrehen "$absoluteDegrees"
            befehlProgrammPause
        } >> "$filePart2"
    done

    # output resulting file
    {
        outputNgcComment '# Arbeitsgang Schruppen beginnt hier'
        befehlDrehenAusgangsposition
        cat "$filePart1"
        echo
        outputNgcComment '# Arbeitsgang Schlichten beginnt hier'
        befehlDrehenAusgangsposition
        befehlSpindelAus
        befehlProgrammPause
        echo
        cat "$filePart2"
        befehlSpindelAus
        befehlProgrammEnde
    } | sed 's/\r$//'
    #| sed 's/\r$//' # remove \r (CR)
    #| sed 's/\r$/\r/' # make \r\n (CRLF)
    #| tr -d '\r' # remove \r (CR)
}

main
