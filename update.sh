
INDEX_FILE="README.md"
SIDECAR_FILE="_sidebar.md"

## genarate index.html file(README.md)
echo "# Pyfdtic Documents \n" > $INDEX_FILE
cat $SIDECAR_FILE >> $INDEX_FILE
gsed -i 's/^* /\n## /g' $INDEX_FILE

# echo '\n## AboutMe\n Email: `MjAxNi5ib2IuYmlAZ21haWwuY29t`' >> $INDEX_FILE

git status

echo

gitci
