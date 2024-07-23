#!/usr/bin/env zsh

# Function to concatenate all files
concat_files() {
    local output_file=$1
    echo "# Build Information" > $output_file
    echo "" >> $output_file
    echo "- **Build Type**: $BUILD_TYPE" >> $output_file
    echo "- **Date**: $PUBDATE" >> $output_file
    echo "- **Commit Hash**: $GIT_COMMIT" >> $output_file
    echo "" >> $output_file

    cat \
        ./README.md \
        ./toc.md \
        ./book/README.md
d    >> $output_file
}

# Set metadata variables
AUTHOR="Mikeal Rogers"
TITLE="Truth from Proof"
TAGS="Cryptography, Proof Theory, Philosophy, Computer Science, Dharma"
PUBLISHER="Hear the World Sound"
PUBDATE=$(date +%Y-%m-%d)  # Set current date dynamically
LANGUAGE="en"

# Get the current git commit hash
GIT_COMMIT=$(git rev-parse --short HEAD)

# Check if we are in GitHub Actions environment
if [[ -n $GITHUB_ACTIONS ]]; then
    BUILD_TYPE="autobuild"
else
    BUILD_TYPE="localbuild"
fi

BUILD_INFO="$BUILD_TYPE $PUBDATE $GIT_COMMIT"

# Conversion options
MARKDOWN_EXTENSIONS="footnotes,tables,codehilite,meta,nl2br,smarty,sane_lists,wikilinks,fenced_code,toc"
PAGE_BREAKS_BEFORE="//h:h1"

# Define the concatenated markdown file
OUTPUT_FILE="build.md"

# Define the temporary cover image
TMP_COVER_IMAGE="tmp_cover.jpg"

CSS="./book.css"
FONT_FAMILY="FiraGO"
BASE_COVER_IMAGE="./images/cover.jpg"

# Create a new cover image with overlaid text
convert $BASE_COVER_IMAGE -font FiraGO-Book -gravity NorthEast -pointsize 24 -fill white -annotate +10+10 "$BUILD_INFO" $TMP_COVER_IMAGE

# Concatenate the files with build info
concat_files $OUTPUT_FILE

# Convert txt to markdown using ebook-convert with specified options
ebook-convert "$OUTPUT_FILE" "truth-from-proof.epub" \
--authors "$AUTHOR" \
--title "$TITLE" \
--tags "$TAGS" \
--extra-css $CSS \
--publisher "$PUBLISHER" \
--pubdate "$PUBDATE" \
--markdown-extensions "$MARKDOWN_EXTENSIONS" \
--embed-font-family "$FONT_FAMILY" \
--no-default-epub-cover \
--page-breaks-before "$PAGE_BREAKS_BEFORE" \
--cover "$TMP_COVER_IMAGE" \
--preserve-cover-aspect-ratio \
--preserve-spaces \
--chapter "//*[name()='h1' or name()='h2' or name()='h3']" --level1-toc "//*[name()='h1']" --level2-toc "//*[name()='h2']" --level3-toc "//*[name()='h3']" \
--pretty-print

echo "Conversion complete!"
