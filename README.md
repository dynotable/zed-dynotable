# DynoTable for Zed

This extension connects Zed to [DynoTable](https://dynotable.com), the DynamoDB client. DynoTable
gives the language features for your DynoTable SQL and PartiQL files.

## What works

- Completion, diagnostics, hover and formatting.
- Rename of table aliases.
- Inlay hints, when you switch them on: set `"inlay_hints": {"enabled": true}` in your Zed
  settings.
- DynoTable SQL files: `.dtsql` and `.dynotable.sql`.
- PartiQL files: `.partiql`.

The extension does not attach to plain `.sql` files.

## Run a statement

Click the ▶ in the gutter next to a statement. Zed saves the file, runs the statement and prints its
rows as a table in the terminal panel, with a summary line under the table.

Run uses `dynotable-lsp` from your `PATH`. When it is not on your `PATH`, Run uses the copy that the
extension installed from npm, in Zed's default data folder on macOS and Linux. So you do not have
to install anything more.

Some statements get no ▶, for example statements after a PartiQL `INSERT` that Zed's SQL grammar
does not parse. Put the cursor in the statement and run "task: spawn", then pick "DynoTable: Run
statement". To give the task a key, run "zed: open keymap file" and add:

```json
{
  "context": "Editor && mode == full",
  "bindings": {
    "ctrl-alt-q": ["task::Spawn", {"task_name": "DynoTable: Run statement"}]
  }
}
```

Use a key that is free in your keymap.

A file with a syntax error has no runnable statements. A PartiQL write does not run from the editor:
make writes in DynoTable.

Run uses the profile of `.dynotable.json` in the root of your project, else your only profile. It
does not read `initialization_options` from your Zed settings. See
[Pick a profile](#pick-a-profile).

On Windows, the ▶ does not work, because the task needs `sh`. Install the CLI with
`npm install -g dynotable-cli`, run "zed: open tasks" and add a task of your own. Then run it with
"task: spawn":

```json
[
  {
    "label": "DynoTable: Run statement (Windows)",
    "command": "dynotable-lsp run --zed",
    "cwd": "$ZED_WORKTREE_ROOT"
  }
]
```

## What does not work

- OpenSearch files (`.opensearch`) are not supported yet.

## Requirements

- macOS on Apple silicon, Linux x64 or Windows x64. `dynotable-lsp` has no binary for other
  platforms yet.
- DynoTable 1.20.0 or later, with the Editor integration switched on.
- `dynotable-lsp` on your `PATH`, or nothing: when `dynotable-lsp` is not on your `PATH`, the
  extension installs the latest `dynotable-cli` from npm.
- Run needs `dynotable-cli` 0.1.2 or later. With an older version, the task tells you to update it.

When DynoTable is not running, a start of the language server starts DynoTable with no
window.

## Pick a profile

Put a `.dynotable.json` file in the root of your project:

```json
{"profile": "dev"}
```

The value is a profile id or slug. With no `.dynotable.json`, DynoTable uses your profile when you
have exactly one.

## After you quit DynoTable

Zed shows the language server as stopped, and Zed does not start it again. To get the features
back:

1. Start DynoTable.
2. Run "editor: restart language server".

## License

MIT. The highlighting queries in `languages/*/highlights.scm` are copied from
[zed-extensions/sql](https://github.com/zed-extensions/sql) (MIT, Copyright (c) 2024 evrsen).
