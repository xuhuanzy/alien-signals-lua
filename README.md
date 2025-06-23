# Alien Signals Lua

**中文** | [English](./README.en.md)

适用于 lua 5.4 的响应式系统.

移植于 [stackblitz/alien-signals](https://github.com/stackblitz/alien-signals).

## 安装

将 [alien-signals](./alien-signals) 目录下的文件复制到项目中.

### 编辑器支持

推荐安装 EmmyLua 插件以获得更好的开发体验：

- **VSCode**: 安装 [emmylua-luals](https://marketplace.visualstudio.com/items?itemName=xuhuanzy.emmylua-luals) 或者 [emmylua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua)
- **其他编辑器**: 搜索 `emmylua` 插件
- **IDEA 系列**: 使用 `emmylua2`

**关于 emmylua-luals**: 由我维护，相比原版更人性化（去掉了自带的调试器，添加了语言服务器配置项i18n），但在语言服务器功能上没有区别。

**为什么不用 luals**: 因为 EmmyLua 已经用 Rust 重构，并且提供了更多功能如泛型支持、命名空间支持等。当然最重要的一点是我是 emmylua-rust 的主要维护者之一，有功能需求我可以加。


## 使用

看 [tests](./tests) 目录下的测试用例.

## 许可证

[MIT](./LICENSE)