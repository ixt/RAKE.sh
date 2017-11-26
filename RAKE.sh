#!/bin/bash
# CC-0 2017
set -euo pipefail
IFS=$'\n\t'

DIR=$(dirname $0)
WHICHLIST="smart"
file=$1

# First we need to pull in the stop lists
load_stoplist(){ 
    # choose list
    case ${WHICHLIST} in
        smart)
            stoplist="./SmartStoplist.txt"
            ;;
        fox)
            stoplist="./FoxStoplist.txt"
            ;;
        *)
            echo "err, no such stoplist" && exit 1
            ;;
    esac

    _stoplist=$(mktemp)
    # Remove comments
    sed -e "/^#/d" ${stoplist} > ${_stoplist}

    # Build Regex pattern file
    regex_stoplist=$(mktemp)
    while read stopword; do
        echo "\\\b${stopword}\\\b" >> ${regex_stoplist}
    done < ${_stoplist}

    echo "${regex_stoplist}"
}

split_into_words(){
    # Seperate a given input file into a temp output file list of words
    input=$1
    words=$(mktemp)

    sed -e "s/[^a-zA-Z0-9_\\+\\-]/\n/g" $input > $words

    # also remove all words made purely from digits & make the rest lowercase
    sed -i -e "/^[0-9]*$/d" -e 's/\(.*\)/\L\1/' $words 

    echo ${words}
}

split_into_sentences(){
    # Pass as a file to function will output a file
    split_sentences=$(mktemp)
    sed -e "s/[\.\!\?,;:\t\"\(\)\'\’\–]/\n/g;s/\s\-\s/\n/g" ${1} \
        | sed -n "/.*[A-Za-z0-9]/p" | sed -e "s/^\s*//g;s/\s*$//g" > ${split_sentences}
    echo ${split_sentences}
}

generate_candidate_words(){
    # First var is sentences, second is pattern db
    sentences=$1
    patterns=$2
    # Split each sentence into phrases using stop words 
    phrases=$(mktemp)
    _sentences=$(mktemp)
    cp $sentences $_sentences

    while read regex; do
        sed -i -e "s/${regex}/|/g" $_sentences
    done < $patterns
    
    while read sentence; do
        IFS='|' read -r -a _array <<< "$sentence"
        for item in ${_array[*]}; do
            [ ! "${item}" == "" ] && echo "${item}" >> ${phrases}
        done
    done < ${_sentences}

    echo ${phrases}
}

calculate_word_scores(){
    phrases=${1}
    # Accepts file as first arg, this should be a list of phrases
    word_scores=$(mktemp)
    word_values=$(mktemp)

    # For every word you rank it by frequency and degree from start of phrase
    while read phrase; do
        words=$(split_into_words <( echo "${phrase}" ))
        WORDSLENGTH=$(wc -l "${words}" | cut -d" " -f1)
        WORDSDEGREE=$(( $WORDSLENGTH - 1 ))
        
        # check if each word is in the list then add it or act 
        while read word; do 
            if egrep -q "^$word," $word_values; then
                LINE=$(grep -n "^$word," $word_values)
                NO=$(cut -d":" -f1 <<< "$LINE")
                WORD_DEGREE=$(cut -d"," -f2 <<< "$LINE")
                WORD_FREQUENCY=$(cut -d"," -f3 <<< "$LINE")
                
                WORD_DEGREE=$(bc -l <<< "$WORD_DEGREE + $WORDSDEGREE" )
                WORD_FREQUENCY=$(bc -l <<< "$WORD_FREQUENCY + 1" )

                sed -i ${NO}d $word_values
                echo "$word,$WORD_DEGREE,$WORD_FREQUENCY" >> ${word_values}
            else
                echo "$word,$WORDSDEGREE,1" >> ${word_values}
            fi
        done < ${words}

    done < ${phrases}

    # add frequency to degree and thats the score!
    while read line; do
        word=$(cut -d"," -f1 <<< "$line")
        WORD_DEGREE=$(cut -d"," -f2 <<< "$line")
        WORD_FREQUENCY=$(cut -d"," -f3 <<< "$line")
        WORD_DEGREE=$(bc -l <<< "$WORD_DEGREE + $WORD_FREQUENCY" )
        WORD_SCORE=$(bc -l <<< "scale=1;$WORD_DEGREE / $WORD_FREQUENCY * 1.0")
        echo "$word,$WORD_SCORE" >> ${word_scores}
    done < ${word_values}

    echo ${word_scores}
}

generate_candidate_keyword_scores(){
    phrases=$1 
    scores=$2
    candidates=$(mktemp)
    while read phrase; do
        words=$(split_into_words <(echo "$phrase")) 
        PHRASE_SCORE="0"
        FILESIZE=$(ls -l $words | cut -d" " -f 5)
        while read word; do 
            LINE=$(grep "^$word," $scores)
            WORD_SCORE=$(cut -d"," -f2 <<< "$LINE")
            PHRASE_SCORE=$(bc -l <<< "$PHRASE_SCORE + $WORD_SCORE")
        done < <(sed -e "/^\s*$/d" ${words})
        echo "${PHRASE_SCORE},${phrase}" >> ${candidates} 
    done < <(sed -e "/^\s*$/d" -e "s/^\s*//g;s/\s*$//g" ${phrases})
    echo ${candidates}
}


main(){
    patterns=$(load_stoplist)
    sentences=$(split_into_sentences ${file})
    phrases=$(generate_candidate_words ${sentences} ${patterns})
    wordscores=$(calculate_word_scores ${phrases})
    candidates=$(generate_candidate_keyword_scores ${phrases} ${wordscores})

    cat $candidates | sort -n | sed -e "s/,/\t-\t/"
    
}

pushd $DIR
main $@
popd
