# Alien Signals Lua

[中文](./README.md) | **English**

A reactive system for Lua 5.4.

Ported from [stackblitz/alien-signals](https://github.com/stackblitz/alien-signals).

## Installation

Copy the files from the [alien-signals](./alien-signals) directory to your project.

### Editor Support

We recommend installing the EmmyLua plugin for a better development experience:

- **VSCode**: Install [emmylua-luals](https://marketplace.visualstudio.com/items?itemName=xuhuanzy.emmylua-luals) or [emmylua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua)
- **Other Editors**: Search for `emmylua` plugins
- **IntelliJ IDEA Series**: Use `emmylua2`

**About emmylua-luals**: Maintained by me, more user-friendly compared to the original version (removed built-in debugger, added language server configuration i18n), but no difference in language server functionality.

**Why not use luals**: Because EmmyLua has been rewritten in Rust and provides more features like generic support, namespace support, etc. Most importantly, I'm one of the main maintainers of emmylua-rust, so I can add features as needed.

## Usage

See the test cases in the [tests](./tests) directory.

## License

[MIT](./LICENSE) 