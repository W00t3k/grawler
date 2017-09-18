#!/bin/bash

program_name=$0

GIT_DIR=
WORK=/tmp
FILTER=
EXTRACT=

SSN_EXTRACT='[0-9]{3}-[0-9]{2}-[0-9]{4}'
PW_EXTRACT='-i password'
SECRET_EXTRACT='-i secret'
KEY_EXTRACT='-i key'
COMMITS=false

SCRIPT_DIR=`pwd -P`


usage() {
	echo "usage: $program_name [-shC] [-g dir] [-w dir] [-f filter] [-x regex]"
	echo "	-g 	git directory"
	echo "	-w 	working directory"
	echo "	-f 	filter for git log"
	echo "	-x 	extract: (p) Password, (k) Keys, (c) Secrets, (s) SSN"
	echo "	-h 	print this cruft"
	echo "  -C 	print commit hashes"
	echo "Only one type of extract may be performed at a time"
}

dump_blob() {
	# the reason we have to do all this very explicit branching is because if we start evaling,
	# then the $0 in the awk match statement evals to the global $0, ie the name of the script
	# but to make things more flexible started using python extractor.py instead of awk
	# hopefully we can condense this then
	commit_hash=$1
	if [ $EXTRACT == "s" ]; then
		if [ "$COMMITS" = true ]; then
			git cat-file -p $1 | egrep '[0-9]{3}-[0-9]{2}-[0-9]{4}' | python ${SCRIPT_DIR}/extractor.py --ssn -H $commit_hash
		else
			# git cat-file -p $1 | egrep '[0-9]{3}-[0-9]{2}-[0-9]{4}' | awk 'match($0, /[0-9]{3}-[0-9]{2}-[0-9]{4}/) { print substr( $0, RSTART, RLENGTH)}'
			git cat-file -p $1 | egrep '[0-9]{3}-[0-9]{2}-[0-9]{4}' | python ${SCRIPT_DIR}/extractor.py --ssn
				# awk 'match($0, /[0-9]{3}-[0-9]{2}-[0-9]{4}/) { print substr( $0, RSTART, RLENGTH)}'
		fi
	elif [ $EXTRACT == "p" ]; then
		git cat-file -p $1 | egrep -i 'password|pw' | python ${SCRIPT_DIR}/extractor.py --password
	elif [ $EXTRACT == "k" ]; then
		git cat-file -p $1 | egrep -i 'key' | python ${SCRIPT_DIR}/extractor.py --key
	elif [ $EXTRACT == "c" ]; then
		git cat-file -p $1 | egrep -i 'secret' | python ${SCRIPT_DIR}/extractor.py --secret
	fi
}

walk_tree() {
	# params 
	# hash = $1
	type=$(git cat-file -t $1)
	if [ "$type" = "blob" ]; then
		dump_blob $1
	else
		# git cat-file -p $2 | cut -d " " -f 3 | cut -d "	" -f 1
		subtrees=$(git cat-file -p $1 | cut -d " " -f 3 | cut -d "	" -f 1)
		for tree in $subtrees; do
			walk_tree $tree
		done
	fi
}

while getopts "g:w:f:x:shC" opt; do
	case $opt in
		g)
			GIT_DIR=$OPTARG
			echo "Git directory is $GIT_DIR"
			;;
		w)
			WORK=$OPTARG
			echo "Working directory is $WORK"
			;;
		f)
			FILTER=$OPTARG
			echo "Grep filter is $FILTER"
			;;
		x)
			EXTRACT=$OPTARG
			echo "Extract command is $EXTRACT"
			;;
		s)
			EXTRACT=$SSN_EXTRACT
			echo "Extracting SSNs"
			;;
		C)
			COMMITS=true
			echo "Printing commit hashes"
			;;
		h)
			usage
			exit
			;;
	esac
done

# make sure GIT_DIR is set
if [ -z $GIT_DIR ]; then
	echo "-g is required"
	usage
	exit 
fi

# make sure GIT_DIR is a dir
if [ -d $GIT_DIR ]; then
	cd $GIT_DIR
else
	echo "$GIT_DIR is not a directory"
	exit
fi

# prepare working dir
if [ -d $WORK ]; then
	rm $WORK/commit_hashes
	rm $WORK/tree_hashes
else
	echo 'Making work directory $WORK'
	mkdir $WORK
fi

# get the commit hashes that have $filter
git log --pretty=tformat:"%H" -- $FILTER > $WORK/commit_hashes

# get the trees
while read line; do
	if [ -z "$FILTER" ]; then
		git cat-file -p $line^{tree} | \
			cut -d " " -f 3 | cut -d "	" -f 1  >> $WORK/tree_hashes
	else
		git cat-file -p $line^{tree} | grep $FILTER | \
			cut -d " " -f 3 | cut -d "	" -f 1  >> $WORK/tree_hashes
	fi
	
done < $WORK/commit_hashes
	
# iterate through trees looking for blobs
while read line; do
	# walk tree with depth 0
	walk_tree $line
done < $WORK/tree_hashes
