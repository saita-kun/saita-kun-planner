#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
FIXTURES="tools/fixtures/quotes"
SPEC="$FIXTURES/quotes-fixture.json"
TMP_ROOT="${TMPDIR:-/tmp}/saita-check-quotes-$$"

trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT"

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

assert_passes() {
  local review="$1" expected_count="${2:-}"
  local output
  if output=$(bash tools/check-quotes.sh "$SPEC" "$review" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' && ! printf '%s\n' "$output" | grep -q '^FAIL:' &&
       { [ -z "$expected_count" ] || printf '%s\n' "$output" | grep -qF "($expected_count quotation(s) verified)"; }; then
      pass
    else
      fail "check-quotes passing output should include OK, no FAIL and expected count $expected_count: $review :: $output"
    fi
  else
    fail "check-quotes should pass: $review :: $output"
  fi
}

assert_warns_with() {
  local review="$1" expected="$2"
  local output
  if output=$(bash tools/check-quotes.sh "$SPEC" "$review" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' &&
       printf '%s\n' "$output" | grep '^WARN:' | grep -qF -- "$expected"; then
      pass
    else
      fail "check-quotes should pass with WARN containing $expected: $review :: $output"
    fi
  else
    fail "check-quotes should not fail on WARN-only case: $review :: $output"
  fi
}

assert_fails_with() {
  local spec="$1" review="$2" expected="$3"
  local output status
  output=$(bash tools/check-quotes.sh "$spec" "$review" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-quotes should fail: $review :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-quotes failure for $review should include $expected :: $output"
  fi
}

write_quote_row() {
  printf '| clause_id | quoted_text |\n| --- | --- |\n| %s | %s |\n' "$2" "$3" > "$TMP_ROOT/$1.md"
}

assert_result() {
  local spec="$1" review="$2" expected_status="$3" expected_output="$4"
  local output status
  output=$(bash tools/check-quotes.sh "$spec" "$review" 2>&1)
  status=$?
  if [ "$status" -eq "$expected_status" ] && [ "$output" = "$expected_output" ]; then
    pass
  else
    fail "check-quotes result for $review: expected status $expected_status / $expected_output; got $status / $output"
  fi
}

# Exact quotations resolve, and rows without a clause citation are skipped.
assert_passes "$FIXTURES/review-green.md" 2

# Literal values are checked against a fake spec, including values used as IDs.
ORIGINAL_SPEC="$SPEC"
SPEC="$TMP_ROOT/literal-spec.json"
cat > "$SPEC" <<'EOF'
{"clauses":[
  {"clause_id":"clause-1","text":"なし 該当なし — - -- --- – n/a na 無し"},
  {"clause_id":"na","text":"該当なし"},
  {"clause_id":"-","text":"-"}
]}
EOF
for value in "なし" "該当なし" "—" "-" "--" "---" "–" "n/a" "na" "無し"; do
  write_quote_row literal_placeholder_values_verified clause-1 "$value"
  assert_passes "$TMP_ROOT/literal_placeholder_values_verified.md" 1
  assert_fails_with "$ORIGINAL_SPEC" "$TMP_ROOT/literal_placeholder_values_verified.md" "quoted_text not found in clauses[].text"
done

write_quote_row literal_na_id_verified na "該当なし"
assert_passes "$TMP_ROOT/literal_na_id_verified.md" 1
assert_fails_with "$ORIGINAL_SPEC" "$TMP_ROOT/literal_na_id_verified.md" "unknown clause_id: na"
write_quote_row literal_na_id_mismatch na "—"
assert_fails_with "$SPEC" "$TMP_ROOT/literal_na_id_mismatch.md" "quoted_text not found in clauses[].text"

write_quote_row legacy_empty_row_compatible - -
assert_passes "$TMP_ROOT/legacy_empty_row_compatible.md" 1
printf '{"clauses":[{"clause_id":"-","text":"該当なし"}]}\n' > "$TMP_ROOT/dash-mismatch-spec.json"
assert_fails_with "$TMP_ROOT/dash-mismatch-spec.json" "$TMP_ROOT/legacy_empty_row_compatible.md" "quoted_text not found in clauses[].text"

# Empty quotations remain invalid even when the ID resembles an empty-row marker.
for clause_id in clause-1 na -; do
  for quoted_text in "" "   " '` `'; do
    write_quote_row empty_quote_rejected "$clause_id" "$quoted_text"
    assert_fails_with "$SPEC" "$TMP_ROOT/empty_quote_rejected.md" "quoted_text is missing for clause: $clause_id"
  done
done
SPEC="$ORIGINAL_SPEC"
assert_passes "$TMP_ROOT/legacy_empty_row_compatible.md" 0
assert_warns_with "$TMP_ROOT/legacy_empty_row_compatible.md" "no clause quotation rows found"

# A table with no data rows is not an error, but it is reported.
assert_passes "$FIXTURES/review-no-rows.md" 0
assert_warns_with "$FIXTURES/review-no-rows.md" "no clause quotation rows found"

# Whitespace-only differences stay green with a WARN (same verbatim rule as check-spec).
assert_warns_with "$FIXTURES/review-whitespace.md" "matches clauses[].text only after whitespace normalization"

# Quotations that do not exist in clauses[].text are the fabrication-risk case.
assert_fails_with "$SPEC" "$FIXTURES/review-fabricated.md" "quoted_text not found in clauses[].text"
assert_fails_with "$SPEC" "$FIXTURES/review-unknown-clause.md" "unknown clause_id: clause-9"
assert_fails_with "$SPEC" "$FIXTURES/review-missing-quote.md" "quoted_text is missing for clause: clause-1"
assert_fails_with "$SPEC" "$FIXTURES/review-no-table.md" "clause-verifier table not found"

# A quotation without a clause_id cannot be traced back to the guidelines.
cat > "$TMP_ROOT/review-missing-clause-id.md" <<'EOF'
# review

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |
| 補助上限の確認 |  | 補助上限額は50万円 | 一致 | green | 低 |
EOF
assert_fails_with "$SPEC" "$TMP_ROOT/review-missing-clause-id.md" "clause_id is missing for quoted_text"

# Input errors are reported instead of silently passing.
assert_fails_with "$SPEC" "$TMP_ROOT/missing-review.md" "review not found"
assert_fails_with "$TMP_ROOT/missing-spec.json" "$FIXTURES/review-green.md" "spec not found"

printf 'not json\n' > "$TMP_ROOT/broken-spec.json"
assert_fails_with "$TMP_ROOT/broken-spec.json" "$FIXTURES/review-green.md" "spec invalid JSON"

printf '{"subsidy_id": "quotes-fixture"}\n' > "$TMP_ROOT/no-clauses-spec.json"
assert_fails_with "$TMP_ROOT/no-clauses-spec.json" "$FIXTURES/review-green.md" "spec has no clauses[]"

# table_outer_pipes_optional: header, delimiter, and body formats are independent.
formats=('%s' '| %s' '%s |' '| %s |')
quotes=('対象経費の3分の2以内' '対象 経費の3分の2以内' '検査用の不一致引用')
statuses=(0 0 1)
outputs=(
  'OK: quote checks passed (2 quotation(s) verified)'
  $'WARN: line 4: clause-2: quoted_text matches clauses[].text only after whitespace normalization: 対象 経費の3分の2以内\nOK: quote checks passed (2 quotation(s) verified)'
  'FAIL: line 4: clause-2: quoted_text not found in clauses[].text (classify as fabrication risk): 検査用の不一致引用'
)
for header_format in "${formats[@]}"; do
  for separator_format in "${formats[@]}"; do
    for row_format in "${formats[@]}"; do
      for case_index in 0 1 2; do
        {
          printf "$header_format\n" 'clause_id | quoted_text'
          printf "$separator_format\n" ':--- | ---:'
          printf "$row_format\n" 'clause-1 | 補助上限額は50万円'
          printf "$row_format\n" "clause-2 | ${quotes[$case_index]}"
        } > "$TMP_ROOT/table_outer_pipes_optional.md"
        assert_result "$SPEC" "$TMP_ROOT/table_outer_pipes_optional.md" \
          "${statuses[$case_index]}" "${outputs[$case_index]}"
      done
    done
  done
done

good_table=$'| clause_id | quoted_text |\n| --- | --- |\n| clause-1 | 補助上限額は50万円 |'
bad_table=$'clause_id | quoted_text\n--- | ---\nclause-9 | 検査用の引用'
one_verified='OK: quote checks passed (1 quotation(s) verified)'
two_verified='OK: quote checks passed (2 quotation(s) verified)'

# Rows can change their outer pipe style within the same table.
{
  printf '%s\n' "$good_table"
  for row_format in "${formats[@]}"; do
    printf "$row_format\n" 'clause-2 | 対象経費の3分の2以内'
  done
} > "$TMP_ROOT/table_outer_pipes_optional_mixed_rows.md"
assert_result "$SPEC" "$TMP_ROOT/table_outer_pipes_optional_mixed_rows.md" 0 \
  'OK: quote checks passed (5 quotation(s) verified)'

# Inline code cells remain table content even with three or more backticks.
for code_ticks in '`' '```' '````'; do
  for table_format in "${formats[@]}"; do
    {
      printf "$table_format\n" "${code_ticks}clause_id${code_ticks} | quoted_text"
      printf "$table_format\n" '--- | ---'
      printf '%s\n' 'clause-1 | 補助上限額は50万円'
      printf "$table_format\n" "${code_ticks}clause-2${code_ticks} | 対象経費の3分の2以内"
    } > "$TMP_ROOT/table_outer_pipes_optional_inline_code.md"
    assert_result "$SPEC" "$TMP_ROOT/table_outer_pipes_optional_inline_code.md" 0 "$two_verified"
    {
      printf '%s\n' "$good_table"
      printf "$table_format\n" "${code_ticks}clause-2${code_ticks} | 対象経費の3分の2以内"
    } > "$TMP_ROOT/table_outer_pipes_optional_inline_code_row.md"
    assert_result "$SPEC" "$TMP_ROOT/table_outer_pipes_optional_inline_code_row.md" 0 "$two_verified"
  done
done

# table_boundaries_respected: blank lines and headings end row collection.
for boundary in '' '   ' '# 総合所見 | 参考' '   ###### 総合所見'; do
  printf '%s\n' "$good_table" "$boundary" '| clause-9 | 表外の通常文 |' \
    > "$TMP_ROOT/table_boundaries_respected.md"
  assert_result "$SPEC" "$TMP_ROOT/table_boundaries_respected.md" 0 "$one_verified"
done
printf '%s\n' "$good_table" '' "$good_table" > "$TMP_ROOT/separate-tables.md"
assert_result "$SPEC" "$TMP_ROOT/separate-tables.md" 0 "$two_verified"

# Lists, block quotes, and thematic breaks end a table without a blank line.
for table_format in "${formats[@]}"; do
  for boundary in '- 補足' '+ 補足' '* 補足' '1. 補足' '2) 補足' \
    '   - 補足 | 参考' '- [ ] 補足' '-' '10)' \
    '> 補足' '>補足' '   > 補足 | 参考' '>' '---' '* * *' '___'; do
    {
      printf "$table_format\n" 'clause_id | quoted_text' '--- | ---' \
        'clause-1 | 補助上限額は50万円'
      printf '%s\n' "$boundary" '継続する補足 | 参考'
    } > "$TMP_ROOT/table_boundaries_markdown_blocks.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_markdown_blocks.md" 0 "$one_verified"
    printf '\n%s\n' "$good_table" >> "$TMP_ROOT/table_boundaries_markdown_blocks.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_markdown_blocks.md" 0 "$two_verified"
  done
done

# A two-space list table ends before an unindented paragraph, for every pipe style.
for table_format in "${formats[@]}"; do
  {
    printf '%s\n' '- 引用確認'
    printf "  $table_format\n" 'clause_id | quoted_text' '--- | ---' \
      'clause-1 | 補助上限額は50万円'
    printf '%s\n' 'リスト外の通常文'
  } > "$TMP_ROOT/table_boundaries_list_dedent.md"
  assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_dedent.md" 0 "$one_verified"
  printf '\n%s\n' "$good_table" >> "$TMP_ROOT/table_boundaries_list_dedent.md"
  assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_dedent.md" 0 "$two_verified"
done

# Rows may use less indentation than the table while remaining inside the list.
for list_prefix in '- ' '1. ' '10) ' '   - ' '-    ' '- - '; do
  indent=$(printf '%*s' "${#list_prefix}" '')
  for boundary in '' "${list_prefix}補足" "${indent}# 補足" "${indent}- 補足" \
    "${indent:1}リスト外の通常文"; do
    {
      printf '%s\n' "${list_prefix}引用確認"
      printf '%s\n' "$good_table" | sed "s/^/$indent /"
      printf '%s\n' "${indent}clause-2 | 対象経費の3分の2以内" \
        "$boundary" '続く通常文'
    } > "$TMP_ROOT/table_boundaries_list_item_blocks.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_item_blocks.md" 0 "$two_verified"
  done

  # An ID-only row at the list content indentation must still fail validation.
  {
    printf '%s\n' "${list_prefix}引用確認"
    printf '%s\n' "$good_table" | sed "s/^/$indent/"
    printf '%s\n' "${indent}clause-1"
  } > "$TMP_ROOT/table_missing_quote_in_list.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_in_list.md" \
    'line 5: quoted_text is missing for clause: clause-1'
done

# Leaving a nested item restores the outer item's indentation across blank lines.
{
  printf '%s\n' '- 外側の引用確認' '  - 内側の引用確認' ''
  printf '%s\n' "$good_table" | sed 's/^/    /'
  printf '%s\n' '  親リストの通常文' ''
  printf '%s\n' "$good_table" | sed 's/^/  /'
  printf '%s\n' 'リスト外の通常文'
} > "$TMP_ROOT/table_boundaries_nested_list_dedent.md"
assert_result "$SPEC" "$TMP_ROOT/table_boundaries_nested_list_dedent.md" 0 "$two_verified"

# An ended list must not change missing-quote validation in a subsequent root table.
{
  printf '%s\n' '- 前の項目' '# リスト外の見出し' '' \
    '  clause_id | quoted_text' '  --- | ---' \
    'clause-1 | 補助上限額は50万円' 'clause-1'
} > "$TMP_ROOT/table_missing_quote_after_list.md"
assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_after_list.md" \
  'line 7: quoted_text is missing for clause: clause-1'

# Thematic breaks leave subsequent tables outside list indentation.
for boundary in '- - -' '* * *'; do
  printf '%s\n' "$boundary" '' '  clause_id | quoted_text' '  --- | ---' \
    'clause-1' > "$TMP_ROOT/table_missing_quote_after_thematic_break.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_after_thematic_break.md" \
    'line 5: quoted_text is missing for clause: clause-1'
done

# Empty list items require one padding column beyond the marker width.
for list_marker in '-' '1.' '10)'; do
  indent=$(printf '%*s' "${#list_marker}" '')
  for padding in '' ' ' '  ' '   ' '    ' '     '; do
    {
      printf '%s\n' "${list_marker}${padding}" '' "${indent}clause_id | quoted_text" \
        "${indent}--- | ---" 'clause-1'
    } > "$TMP_ROOT/table_missing_quote_after_empty_list.md"
    assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_after_empty_list.md" \
      'line 5: quoted_text is missing for clause: clause-1'

    {
      printf '%s\n' "${list_marker}${padding}"
      printf '%s\n' "$good_table" | sed "s/^/$indent /"
      printf '%s\n' "${indent}リスト外の通常文"
    } > "$TMP_ROOT/table_boundaries_empty_list_dedent.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_empty_list_dedent.md" 0 "$one_verified"

    printf '%s\n' "${list_marker}${padding}" "${indent}  clause_id | quoted_text" \
      "${indent}  --- | ---" "${indent} clause-1" \
      > "$TMP_ROOT/table_missing_quote_in_empty_list.md"
    assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_in_empty_list.md" \
      'line 4: quoted_text is missing for clause: clause-1'
  done
done

# An empty item followed by a blank line ends before a root quotation table.
for list_marker in '-' '+' '*' '1.' '2)' '10)'; do
  for blank in '' '   '; do
    printf '%s\n' "$good_table" '' "$list_marker" "$blank" \
      '  clause_id | quoted_text' '  --- | ---' \
      'clause-2 | 対象経費の3分の2以内' > "$TMP_ROOT/table_after_empty_item_blank.md"
    assert_result "$SPEC" "$TMP_ROOT/table_after_empty_item_blank.md" 0 "$two_verified"
    printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_after_empty_item_blank.md"
    assert_fails_with "$SPEC" "$TMP_ROOT/table_after_empty_item_blank.md" \
      'line 10: clause-1: quoted_text not found in clauses[].text'
  done
done

# Lazy paragraph continuations retain the item until a subsequent table ends.
for list_prefix in '- ' '1. ' '- - '; do
  indent=$(printf '%*s' "${#list_prefix}" '')
  for continuation in '折り返した説明' '  折り返した説明' "${indent}2. 折り返した説明" '===' '--'; do
    for table_format in "${formats[@]}"; do
      {
        printf '%s\n' "$good_table" '' "${list_prefix}引用確認" "$continuation"
        printf "$indent$table_format\n" 'clause_id | quoted_text' '--- | ---' \
          'clause-1 | 補助上限額は50万円'
        printf '%s\n' 'リスト外の通常文'
      } > "$TMP_ROOT/table_boundaries_lazy_continuation.md"
      assert_result "$SPEC" "$TMP_ROOT/table_boundaries_lazy_continuation.md" 0 "$two_verified"
      printf '%s\n' '' "$good_table" 'clause-1 | 検査用の不一致引用' \
        >> "$TMP_ROOT/table_boundaries_lazy_continuation.md"
      assert_fails_with "$SPEC" "$TMP_ROOT/table_boundaries_lazy_continuation.md" \
        'line 15: clause-1: quoted_text not found in clauses[].text'
    done
  done
done

# Setext headings and paragraph continuations do not open containing lists.
for paragraph in $'見出し\n-' $'通常段落\n+' $'通常段落\n*' \
  $'通常段落\n1.' $'通常段落\n1)' $'通常段落\n0. 続く通常文' $'通常段落\n2. 続く通常文' \
  $'通常段落\n2) 続く通常文' $'通常段落\n+\n2. 続く通常文'; do
  printf '%s\n' "$paragraph" '' '   clause_id | quoted_text' '   --- | ---' \
    'clause-1' > "$TMP_ROOT/table_missing_quote_after_paragraph.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_after_paragraph.md" \
    'quoted_text is missing for clause: clause-1'
done

# Nonempty bullets and ordered items starting at one can interrupt a paragraph.
for list_prefix in '- ' '+ ' '* ' '1. ' '1) ' '01. '; do
  indent=$(printf '%*s' "${#list_prefix}" '')
  {
    printf '%s\n' '導入文' "${list_prefix}引用確認"
    printf '%s\n' "$good_table" | sed "s/^/$indent/"
    printf '%s\n' 'リスト外の通常文'
  } > "$TMP_ROOT/table_boundaries_list_after_paragraph.md"
  assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_after_paragraph.md" 0 "$one_verified"
done

# Paragraph continuation inside an item retains that item's content indentation.
printf '%s\n' '- 引用確認' '  2. 続く通常文' '' \
  '     clause_id | quoted_text' '     --- | ---' '  clause-1' \
  > "$TMP_ROOT/table_missing_quote_in_list_paragraph.md"
assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_in_list_paragraph.md" \
  'line 6: quoted_text is missing for clause: clause-1'

# Fenced examples are ignored, including shorter or different fence markers.
for fence in '```' '~~~'; do
  printf '%s\n' "$good_table" "${fence}${fence}markdown" "$bad_table" \
    "$fence" '```' '~~~' "${fence}${fence}text" "$bad_table" \
    "${fence}${fence}${fence}" "$good_table" > "$TMP_ROOT/fenced-tables.md"
  assert_result "$SPEC" "$TMP_ROOT/fenced-tables.md" 0 "$two_verified"
  printf '%s\n' "${fence}markdown" "$good_table" "$fence" > "$TMP_ROOT/fenced-only.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/fenced-only.md" 'clause-verifier table not found'
done

# List fences pair with indented closers; following tables still get checked.
for fence in '```' '~~~'; do
  for list_prefix in '- ' '+ ' '* ' '1. ' '10) ' '   - ' '-    ' '- - '; do
    indent=$(printf '%*s' "${#list_prefix}" '')
    for close_indent in '' '   '; do
      {
        printf '%s\n' "$good_table" '' "${list_prefix}${fence}text"
        printf '%s\n' "$bad_table" | sed "s/^/$indent/"
        printf '%s\n' "${indent}${close_indent}${fence}" "$good_table"
      } > "$TMP_ROOT/table_boundaries_list_fences.md"
      assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_fences.md" 0 "$two_verified"
      printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_boundaries_list_fences.md"
      assert_fails_with "$SPEC" "$TMP_ROOT/table_boundaries_list_fences.md" \
        'clause-1: quoted_text not found in clauses[].text'
    done

    # Leaving the list also ends an unclosed fence in that list item.
    {
      printf '%s\n' "$good_table" '' "${list_prefix}${fence}text"
      printf '%s\n' "$bad_table" | sed "s/^/$indent/"
      printf '%s\n' "$good_table"
    } > "$TMP_ROOT/table_boundaries_list_fence_dedent.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_list_fence_dedent.md" 0 "$two_verified"
  done
done

# Ordinary tables end paragraphs before ordered lists, even without a blank line.
for fence in '```' '~~~'; do
  for list_prefix in '2. ' '10) '; do
    indent=$(printf '%*s' "${#list_prefix}" '')
    {
      printf '%s\n' "$good_table" '' '判断 | judgment_basis' '--- | ---' '確認 | 根拠' \
        "${list_prefix}${fence}text" "${indent}説明" "${indent}${fence}" "$good_table"
    } > "$TMP_ROOT/table_after_judgment_basis_list_fence.md"
    assert_result "$SPEC" "$TMP_ROOT/table_after_judgment_basis_list_fence.md" 0 "$two_verified"
    printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_after_judgment_basis_list_fence.md"
    assert_fails_with "$SPEC" "$TMP_ROOT/table_after_judgment_basis_list_fence.md" \
      'line 14: clause-1: quoted_text not found in clauses[].text'
  done
done

# Dedented list markers start new items, including changes of list type or delimiter.
for previous_prefix in '- ' '1. ' '10) '; do
  for list_prefix in '+ ' '2. ' '10) '; do
    indent=$(printf '%*s' "${#list_prefix}" '')
    for fence in '```' '~~~'; do
      {
        printf '%s\n' "$good_table" '' "${previous_prefix}引用確認" "${list_prefix}${fence}text"
        printf '%s\n' "$bad_table" | sed "s/^/$indent/"
        printf '%s\n' "${indent}${fence}" "$good_table"
      } > "$TMP_ROOT/table_after_sibling_list_fence.md"
      assert_result "$SPEC" "$TMP_ROOT/table_after_sibling_list_fence.md" 0 "$two_verified"
      printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_after_sibling_list_fence.md"
      assert_fails_with "$SPEC" "$TMP_ROOT/table_after_sibling_list_fence.md" \
        'line 14: clause-1: quoted_text not found in clauses[].text'
    done
  done
done

# HTML blocks exclude quotation rows and fence markers until their own end condition.
html_openers=('<pre>' '   <PRE class="example">' '<script>' '<style>' '<!--' \
  '<?review' '<!REVIEW' '<![CDATA[' '<div>' '<custom-element data-note="a > b">' '</custom-element>')
html_closers=('</pre>' '</PRE>' '</script>' '</style>' '-->' '?>' '>' ']]>' \
  $'</div>\n' $'</custom-element>\n' '')
for html_index in "${!html_openers[@]}"; do
  for fence in '```' '~~~'; do
    printf '%s\n' "$good_table" "${html_openers[$html_index]}" "$fence" "$bad_table" \
      "${html_closers[$html_index]}" "$good_table" > "$TMP_ROOT/table_after_html_block_fence.md"
    assert_result "$SPEC" "$TMP_ROOT/table_after_html_block_fence.md" 0 "$two_verified"
    printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_after_html_block_fence.md"
    assert_fails_with "$SPEC" "$TMP_ROOT/table_after_html_block_fence.md" \
      'clause-1: quoted_text not found in clauses[].text'
  done
done

# HTML comments directly following two-column tables are not quotation rows.
for comment in '<!-- 注記 -->' $'<!--\n注記\n\n別の行\n-->' '<pre>注記</pre>'; do
  for table_format in "${formats[@]}"; do
    printf "$table_format\n" 'clause_id | quoted_text' '--- | ---' \
      'clause-1 | 補助上限額は50万円' > "$TMP_ROOT/table_boundaries_html_comment.md"
    printf '%s\n' "$comment" "$good_table" >> "$TMP_ROOT/table_boundaries_html_comment.md"
    assert_result "$SPEC" "$TMP_ROOT/table_boundaries_html_comment.md" 0 "$two_verified"
  done
done

# List HTML blocks end at a closing tag or when the containing item ends.
for html_closer in '  </pre>' ''; do
  printf '%s\n' "$good_table" '- <pre>' '  ```' '  clause-9 | 検査用の引用' \
    "$html_closer" "$good_table" > "$TMP_ROOT/table_after_list_html_block.md"
  assert_result "$SPEC" "$TMP_ROOT/table_after_list_html_block.md" 0 "$two_verified"
done

# Standalone tags after a dedent start HTML blocks outside the prior paragraph.
for list_prefix in '- ' '1. ' '- - '; do
  indent=$(printf '%*s' "${#list_prefix}" '')
  for tag in '<span>' '<span class="example">' '</span>' '<span/>'; do
    for html_indent in '' "${indent:2}"; do
      {
        printf '%s\n' "$good_table" '' "${list_prefix}引用確認" "${html_indent}${tag}"
        printf '%s\n' "$bad_table" | sed "s/^/$html_indent/"
        printf '%s\n' "${html_indent}"'```' '' "$good_table"
      } > "$TMP_ROOT/table_after_html_list_paragraph_dedent.md"
      assert_result "$SPEC" "$TMP_ROOT/table_after_html_list_paragraph_dedent.md" 0 "$two_verified"
      printf '%s\n' 'clause-1 | 検査用の不一致引用' >> "$TMP_ROOT/table_after_html_list_paragraph_dedent.md"
      assert_fails_with "$SPEC" "$TMP_ROOT/table_after_html_list_paragraph_dedent.md" \
        'line 15: clause-1: quoted_text not found in clauses[].text'
    done

    # At the paragraph's own indentation, a standalone tag remains inline text.
    {
      printf '%s\n' "$good_table" '' "${list_prefix}引用確認" "${indent}${tag}"
      printf '%s\n' "$good_table" | sed "s/^/$indent/"
      printf '%s\n' 'リスト外の通常文'
    } > "$TMP_ROOT/table_after_inline_html_list_paragraph.md"
    assert_result "$SPEC" "$TMP_ROOT/table_after_inline_html_list_paragraph.md" 0 "$two_verified"
  done
done

# Inline HTML inside a quotation cell and tags inside a fence retain their context.
printf '%s\n' "$good_table" '```' '<pre>' '```' "$good_table" \
  > "$TMP_ROOT/table_after_html_inside_fence.md"
assert_result "$SPEC" "$TMP_ROOT/table_after_html_inside_fence.md" 0 "$two_verified"
printf '%s\n' '{"clauses":[{"clause_id":"clause-html","text":"<span>確認済み</span>"}]}' \
  > "$TMP_ROOT/html-cell-spec.json"
printf '%s\n' 'quoted_text | clause_id' '--- | ---' '<span>確認済み</span> | clause-html' \
  > "$TMP_ROOT/table_inline_html_cell.md"
assert_result "$TMP_ROOT/html-cell-spec.json" "$TMP_ROOT/table_inline_html_cell.md" 0 "$one_verified"

# A pipe alone is insufficient: require separate headers and matching delimiters.
for prose in \
  $'clause_id | quoted_text\nclause-1 | 補助上限額は50万円' \
  $'| clause_id | quoted_text |\n| --- | 説明 |\n| clause-1 | 補助上限額は50万円 |' \
  $'| clause_id | quoted_text |\n| --- |\n| clause-1 | 補助上限額は50万円 |' \
  $'clause_id と quoted_text\n---\nclause-1 | 補助上限額は50万円' \
  $'clause_id と quoted_text | 説明\n--- | ---\nclause-1 | 補助上限額は50万円'; do
  printf '%s\n' "$prose" > "$TMP_ROOT/prose-with-pipes.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/prose-with-pipes.md" 'clause-verifier table not found'
done

# table_missing_quote_still_fails: even an ID-only row must report its missing quote.
for row_format in "${formats[@]}"; do
  {
    printf '%s\n' "$good_table"
    printf "$row_format\n" 'clause-1'
  } > "$TMP_ROOT/table_missing_quote_still_fails.md"
  assert_fails_with "$SPEC" "$TMP_ROOT/table_missing_quote_still_fails.md" \
    'line 4: quoted_text is missing for clause: clause-1'
done

# Escaped inner and final pipes stay inside the quotation cell.
printf '%s\n' '{"clauses":[{"clause_id":"clause-pipe","text":"left|right|"}]}' \
  > "$TMP_ROOT/escaped-pipe-spec.json"
for row_format in "${formats[@]}"; do
  {
    printf '%s\n' 'clause_id | quoted_text' '--- | ---'
    printf "$row_format\n" 'clause-pipe | left\|right\|'
  } > "$TMP_ROOT/escaped-pipes.md"
  assert_result "$TMP_ROOT/escaped-pipe-spec.json" "$TMP_ROOT/escaped-pipes.md" 0 "$one_verified"
done

# git_ref_independent: quotation contracts must pass with Git unavailable.
mkdir -p "$TMP_ROOT/bin"
cat > "$TMP_ROOT/bin/git" <<'EOF'
#!/bin/sh
: > "$(dirname "$0")/git-invoked"
echo "FAIL: quotation contracts must not read Git references" >&2
exit 1
EOF
chmod +x "$TMP_ROOT/bin/git"

# One fixture matrix retains every finding from review rounds 1 through 4.
if PATH="$TMP_ROOT/bin:$PATH" python3 - "$TMP_ROOT" "$SPEC" <<'PY'
import contextlib
import hashlib
import importlib.util
import io
import itertools
import json
import pathlib
import re
import sys

root = pathlib.Path.cwd()
temporary = pathlib.Path(sys.argv[1])
spec_path = root / sys.argv[2]
sys.path.insert(0, str(root / "tools/lib"))


def load_checker(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


checker = load_checker("current_quotes", root / "tools/lib/check_quotes.py")
failures = []
checks = 0


def check(condition, label):
    global checks
    checks += 1
    if not condition:
        failures.append(label)


def result(module, spec, review):
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        status = module.main(["check-quotes", str(spec), str(review)])
    errors, warnings, verified = module.check_quotes(spec, review)
    check(status == int(bool(errors)), "CLI status agrees with quotation evaluation")
    return status, verified, output.getvalue()


good = "| clause_id | quoted_text |\n| --- | --- |\n| clause-1 | 補助上限額は50万円 |"
# Columns: review finding, complete Markdown containing the target table.
REVIEW_REGRESSIONS = (
    ("r1_list_fence_closer", "- ~~~text\n  example\n  ~~~\n{table}"),
    ("r1_table_block_boundary", "{table}\n- note\ncontinued note\n"),
    ("r2_continuation_fence", "- note\n  ~~~text\n  example\n     ~~~\n{table}"),
    ("r2_html_comment", "<!--\n~~~\n-->\n{table}\n<!-- note -->"),
    ("r2_list_table_dedent", "- note\n{item_table}\nroot paragraph\n"),
    ("r3_empty_item_blank", "-\n\n  {header}\n  {delimiter}\n{row}"),
    ("r3_ordinary_table", "note | judgment_basis\n--- | ---\nvalue | source\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("r3_html_block", "<pre>\n~~~\n</pre>\n{table}\n<!-- note -->"),
    ("r3_list_lazy_continuation", "- note\ncontinued note\n{item_table}\nroot paragraph\n"),
    ("r4_indented_code", "note | source\n--- | ---\nvalue | source\n    code example\n{table}\n    code example"),
    ("r4_list_start_table", "- | note |\n  | --- |\n  | value |\n{table}"),
    ("r4_quote_lazy_continuation", "> note\ncontinued note\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("indented_code_fence_text", "    ~~~\n    code example\n{table}"),
    ("indented_code_blank", "    code example\n\n    ~~~\n{table}"),
    ("list_relative_indented_code", "- note | source\n  --- | ---\n      ~~~\n{item_table}\nroot paragraph"),
    ("list_start_quote_table", "- {header}\n  {delimiter}\n  {row}\nroot paragraph"),
    ("nested_start_quote_table", "- > {header}\n  > {delimiter}\n  > {row}\nroot paragraph"),
    ("quote_table_dedent", "> {header}\n> {delimiter}\n> {row}\nroot paragraph"),
    ("quote_unclosed_fence", "> ~~~\n> example\n{table}"),
    ("quote_unclosed_html", "> <pre>\n> ~~~\n{table}"),
    ("quote_unclosed_list_fence", "> - ~~~\n>   example\n{table}"),
    ("nested_quote_lazy", "> > note\ncontinued note\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("list_quote_lazy", "- > note\ncontinued note\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("list_lazy_table_header", "- note\n{header}\n  {delimiter}\n  {row}\nroot paragraph"),
    ("quote_lazy_table_header", "> note\n{header}\n> {delimiter}\n> {row}\nroot paragraph"),
    ("nested_lazy_table_header", "- > note\n{header}\n  > {delimiter}\n  > {row}\nroot paragraph"),
    ("ordinary_table_short_separator", "note | source\n-- | --\nvalue | source\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("ordinary_table_aligned_separator", "note | source\n:-: | -----------:\nvalue | source\n2. ~~~\n   example\n   ~~~\n{table}"),
    ("quote_indented_lazy_prose", "> note\n  | clause_id | quoted_text |\n> | --- | --- |\n> | clause-9 | example |\n\n{table}"),
    ("list_partial_indent_lazy_prose", "- note\n | clause_id | quoted_text |\n  | --- | --- |\n  | clause-9 | example |\n\n{table}"),
    ("nested_partial_indent_lazy_prose", "- - note\n   | clause_id | quoted_text |\n    | --- | --- |\n    | clause-9 | example |\n\n{table}"),
)
styles = ("{}", "| {}", "{} |", "| {} |")
separators = ("--- | ---", "- | -", ":-: | --:")
matrix_checks = 0
for (name, template), style, separator, preceding, wrapper, mismatch in itertools.product(
    REVIEW_REGRESSIONS, styles, separators, (False, True), ("root", "list", "quote"), (False, True)
):
    quote = "検査用の不一致引用" if mismatch else "補助上限額は50万円"
    header, delimiter, row = [style.format(value) for value in (
        "clause_id | quoted_text", separator, "clause-1 | " + quote,
    )]
    table = "\n".join((header, delimiter, row))
    text = template.format(table=table, header=header, delimiter=delimiter, row=row,
                           item_table="\n".join("  " + line for line in table.splitlines()))
    if wrapper == "list":
        text = "- container\n\n" + "\n".join("  " + line for line in text.splitlines())
    elif wrapper == "quote":
        text = "\n".join("> " + line for line in text.splitlines())
    if preceding:
        text = good + "\n\n" + text
    review = temporary / "review-regression-matrix.md"
    review.write_text(text + "\n", encoding="utf-8")
    status, verified, output = result(checker, spec_path, review)
    expected = (int(mismatch), int(preceding) + int(not mismatch))
    check((status, verified) == expected and output.count("FAIL:") == int(mismatch) and (
        not mismatch or "clause-1: quoted_text not found in clauses[].text" in output
    ), f"review_regression_matrix {name}/{style}/{separator}/{preceding}/{wrapper}/{mismatch}: "
       f"expected {expected}, got {(status, verified)} :: {output.strip()}")
    matrix_checks += 1
print(f"review_regression_matrix: {len(REVIEW_REGRESSIONS)} cases / {matrix_checks} combinations")

# Frozen tools/lib/check_quotes.py from 22dfff2299762c955e765561d38650302055c24c.
baseline_path = root / "tests/fixtures/check_quotes_legacy.py"
check(hashlib.sha256(baseline_path.read_bytes()).hexdigest() ==
      "c02d8a17a016b96714703be46a06c42c5239358a9da2ea19de0bb2d86a58a231",
      "legacy_snapshot_sha256")
baseline = load_checker("legacy_quotes", baseline_path)

# Discover quotation-bearing Markdown independently of either parser. Include the
# requested roots and this repository's actual fixture and example directories.
scopes = ("docs", "tests/fixtures", "specs", "tools/fixtures", "examples")
corpus = []
specs = []
for scope in scopes:
    for path in sorted((root / scope).rglob("*.md")):
        if any("|" in line and re.search(r"clause_?id", line, re.I)
               and re.search(r"quoted_?text", line, re.I)
               for line in path.read_text(encoding="utf-8").splitlines()):
            corpus.append(path)
    for path in sorted((root / scope).rglob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if isinstance(data, dict) and isinstance(data.get("clauses"), list) and data["clauses"]:
            specs.append(path)
check(len(corpus) >= 6 and spec_path in specs, "legacy differential corpus is nonempty")
comparisons = 0
for review, spec in itertools.product(corpus, specs):
    old = result(baseline, spec, review)
    new = result(checker, spec, review)
    # These existing reviews require no TANE-14 exception. Keep the allowance
    # empty rather than accepting arbitrary status or quotation-count changes.
    check(old[:2] == new[:2], f"legacy_differential {review.relative_to(root)} / "
          f"{spec.relative_to(root)}: legacy={old[:2]}, current={new[:2]}")
    comparisons += 1
print(f"legacy_differential: {len(corpus)} Markdown files / {len(specs)} specs / "
      f"{comparisons} comparisons / 0 allowed corpus differences")

# TANE-14 literal-value behavior stays covered independently of the corpus.
# A real clause ID always takes precedence.
literal_spec = temporary / "literal-value-spec.json"
literal_review = temporary / "literal-value-review.md"
literal_cases = 0
for clause_id, quote in itertools.product(("clause-literal", "na", "-"),
                                         ("なし", "該当なし", "—", "na", "-")):
    literal_spec.write_text(json.dumps({"clauses": [
        {"clause_id": clause_id, "text": quote},
    ]}), encoding="utf-8")
    literal_review.write_text("| clause_id | quoted_text |\n| --- | --- |\n"
                              f"| {clause_id} | {quote} |\n", encoding="utf-8")
    new = result(checker, literal_spec, literal_review)
    check(new[:2] == (0, 1), f"literal_placeholder_values_verified {clause_id}/{quote}: {new}")
    literal_cases += 1
print(f"literal_placeholder_values_verified: {literal_cases} cases")
check(not (temporary / "bin/git-invoked").exists(), "git_ref_independent")
for failure in failures:
    print("FAIL: " + failure)
print(f"quote_contracts: {checks - len(failures)} pass / {len(failures)} fail")
raise SystemExit(bool(failures))
PY
then
  pass
else
  fail "quotation structure, legacy differential, and literal-value contracts"
fi

echo "=== test-check-quotes: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
