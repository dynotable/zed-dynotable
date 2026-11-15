# DynoTable for Zed

This extension connects Zed to [DynoTable](https://dynotable.com), the DynamoDB client. DynoTable
gives the language features for your DynoTable SQL and PartiQL files.

## What works

- Completion, diagnostics, hover, formatting, rename and inlay hints.
- DynoTable SQL files: `.dtsql` and `.dynotable.sql`.
- PartiQL files: `.partiql`.

The extension does not attach to plain `.sql` files.

## What does not work

- There is no results grid. Run your queries in the DynoTable app or in the DynoTable extension for
  VS Code.
- OpenSearch files (`.opensearch`) are not supported yet.

## Requirements

- DynoTable 1.20.0 or later, with the Editor integration switched on.
- `dynotable-lsp` on your `PATH`, or nothing: when `dynotable-lsp` is not on your `PATH`, the
  extension installs the latest `dynotable-cli` from npm.

When DynoTable is not running, the first start of the language server starts DynoTable with no
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
