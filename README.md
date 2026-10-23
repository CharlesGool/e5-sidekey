# 侧键开关热点 · Side Key Hotspot

单击侧键打开热点页，长按震动并开关热点

*Tap the side key for the hotspot page, hold it to turn the hotspot on or off*

容悦 E5（OpenWrt）信息屏应用。当前版本 **v1.4**，应用 ID `sidekey`。

## 安装

1. 下载 [`releases/sidekey-v1.4.tar.gz`](releases/sidekey-v1.4.tar.gz)。
2. 在信息屏的「应用管理」中安装（LuCI：服务 → 信息屏应用 → 应用管理）。
3. 安装后文件位于设备上的 `/etc/e5-infoscreen/plugins/sidekey/`。

## 设置

加粗为默认值。

- 长按侧键（Holding the side key）：**开关热点**；和单击一样，打开热点页（原样）
- 长按时间（Hold for）：0.5 秒；**0.8 秒**；1.2 秒；2 秒
- 熄屏时也能开关（Also with the screen dark）：默认开  
  <sub>关闭后，熄屏时长按侧键只点亮屏幕；单击始终只点亮屏幕</sub>
- 按键锁定时也能长按开关（Also with the keys locked）：默认开  
  <sub>包括音量键关闭屏幕、电源键 + * 锁定；屏幕保持关闭，单击仍不起作用</sub>
- 震动（Vibration）：不震动；短；**中**；长

## 源码

`sidekey/` 是当前版本安装包解压后的内容：

- [`backend.uc`](sidekey/backend.uc)
- [`early.html`](sidekey/early.html)
- [`index.html`](sidekey/index.html)
- [`manifest.json`](sidekey/manifest.json)
- [`patch.js`](sidekey/patch.js)

## 版本

- [v1.4](releases/sidekey-v1.4.tar.gz)（当前）：修复熄屏（含音量键关闭屏幕）时长按侧键没反应——上游的电源键菜单在熄屏时会拦下除电源、音量以外的所有按键，现在侧键的监听排在它前面
- [v1.3](releases/sidekey-v1.3.tar.gz)
- [v1.2](releases/sidekey-v1.2.tar.gz)
- [v1.1](releases/sidekey-v1.1.tar.gz)
- [v1.0](releases/sidekey-v1.0.tar.gz)
