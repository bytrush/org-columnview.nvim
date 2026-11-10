# AGENTS.md

## Example-file learnings

- Dynamic blocks use `#+BEGIN: columnview` / `#+END:` (the `#+BEGIN_COLUMNVIEW`
  form is not an Org dynamic block). Keep the `columnview` name on the BEGIN
  line.
- Keep `#+TITLE` / `#+COLUMNS` / `#+PROPERTY` directive lines contiguous and do
  not mention literal `#+...` directives inside comments. nvim-orgmode's
  directive parsing can drop or misparse the real directives otherwise.
- Regenerate dblock tables with
  `:lua require('org-columnview.dblock').update_all()` after changing dblock
  rendering; the generated tables are aligned and idempotent, so avoid
  hand-editing them.
