# Shrink Ciqual's compo*.xml to the constituents this pipeline reads.
#
# The published file is about 70 MB: 74 constituents for each of 3,484 foods, each
# one a block carrying a value, a min, a max, a confidence code and a source. Of
# those 74, `ciqual.CONST_SPECS` reads 9, so keeping only their blocks leaves about
# a tenth of the file with every food still in it. That matters when the file has
# to be moved around: truncating compo*.xml by length instead keeps all 74
# constituents for the first few hundred foods and silently drops the rest, which
# builds without complaint and leaves most of the table with no energy value.
#
# Whole blocks are kept rather than rewritten, so the output is the real export
# with rows removed and nothing reformatted. The header and <TABLE> pass through
# untouched, which keeps the result valid XML.
#
#   awk -f trim_compo.awk compo_2025_11_03.xml > compo_small.xml
#
# Keep the codes below in step with CONST_SPECS in fooddb/ciqual.py. They are the
# primary and alternate codes for the eight nutrients the app stores; a code that
# an edition does not publish is simply never matched.

BEGIN {
    split("328 25000 25001 31000 40000 40302 34100 32000 10110", codes, " ")
    for (i in codes) want[codes[i]] = 1
}

/<COMPO>/ { inside = 1; n = 0; keep = 0 }

inside {
    buf[++n] = $0
    if ($0 ~ /<const_code>/) {
        code = $0
        gsub(/[^0-9]/, "", code)
        if (code in want) keep = 1
    }
    if ($0 ~ /<\/COMPO>/) {
        if (keep) for (i = 1; i <= n; i++) print buf[i]
        inside = 0
    }
    next
}

{ print }
