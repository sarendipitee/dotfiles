#!/bin/zsh

set -e


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SPLICE_DIR="$HOME/Music/Splice/sounds/"

echo $files

echo Searching for .wav files in $SCRIPT_DIR

count=0
for file in "$SCRIPT_DIR"/**/*.wav; do
	hex=$(hexdump "$file" | head -c 47)
	count=`expr $count + 1`
	if [[ "$hex" == "0000000 0000 0000 0000 0000 0000 0000 0000 0000" ]]; then
		echo "Found bad file $file"
		#res=$(find "$SPLICE_DIR" -iname "$(basename $file)" -exec echo "found file @ {}" \;)
		search_result=$(find "$SPLICE_DIR" -iname "$(basename $file)")
		if [[ -n "$search_result" ]]; then
			echo "Found matching splice file for $(basename file)"
			echo "copying $search_result"
			cp $search_result $file
		fi
		echo --------
	fi
done;
echo Done. Scanned $count files

