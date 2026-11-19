# Subject

Fills the **subject** of outgoing mail for **World of Warcraft: Forever** (`Interface: 16001`).

- Attach an item: the subject becomes the first attached item's name (`Linen Cloth x20` for stacks).
- Send money without an item: the subject becomes the amount (`Money: 12g 5s 3c`).
- A subject you typed yourself is never overwritten. Only an empty subject, or one this addon set, is replaced.

## Configuration

Flags live in [`subject/Config.lua`](subject/Config.lua):

| Flag | Default | Effect |
| --- | --- | --- |
| `ENABLED` | `true` | Master switch |
| `FROM_ITEM` | `true` | Subject from first attached item |
| `FROM_MONEY` | `true` | Subject from money amount when no item is attached |
| `SHOW_ITEM_COUNT` | `true` | Append ` x<count>` for stacks |

## Development

```bash
lua tests/test_subject.lua      # pure Lua tests
./scripts/publish-local.sh           # copy to Forever AddOns, then /reload
```

Release flow: see [`docs/RELEASE.md`](docs/RELEASE.md).

## License

MIT, see [`LICENSE`](LICENSE).
