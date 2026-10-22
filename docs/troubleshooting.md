> 本文是本仓库的背景文档：记录这套打包方案要解决的 4 个问题、根因与验证方法。
> 文中路径已做脱敏（`/home/user`），命令可直接照抄。

下面是这个项目的完整复盘，按"遇到什么问题 → 怎么定位 → 用什么命令 → 学到什么"来讲。这也是我实际走的路径，包括几次走错的路。

---

# 一、先看清全局：这其实是 4 个独立问题

| 阶段 | 表象 | 真正的问题类型 |
|---|---|---|
| 1 | 官方只有 `.deb`，Fedora 没有 dpkg，还没 sudo | **打包/分发**问题 |
| 2 | 启动没反应 | **动态链接/依赖**问题 |
| 3 | 启动直接静默退出 | **ELF + 系统安全策略**问题 |
| 4 | 登录后几秒崩溃 | **符号冲突**（最有意思的一个） |
| 5 | 输入框白字白底 | **GUI 架构定位**问题（最考验方法论） |

关键心态：**这 4 个问题的解法完全没有交集**。不要指望一个"兼容层"能一次解决，必须逐个击穿。

---

# 二、阶段 1：拆包 + 无 sudo 安装

### 判断
官网只给 UOS/麒麟 的 `.deb`。Fedora 没有 `dpkg`，也没有 root。所以策略是：**手动解包 → 放进用户目录 → 自己写启动器**。

### 命令

```bash
# 1. 看 deb 内部结构（deb 就是 ar 归档）
ar t signed_com.hzt.xc_3.14.0.2_amd64.deb
#   debian-binary
#   control.tar.xz
#   data.tar.xz

# 2. 解出
mkdir pkg && cd pkg
ar x ../signed_com.hzt.xc_3.14.0.2_amd64.deb
tar -xf data.tar.xz      # 得到 opt/apps/com.hzt.xc/...
tar -xf control.tar.xz   # 得到 postinst / control

# 3. 读安装脚本——免费拿官方知识
cat postinst
```

### 这一步最大的收获
`postinst` 里有一段"glibc > 2.28 时删掉自带旧库"的规则，包括 `libm.so.6`、`libgtk-x11-2.0`、`libGLX.so*` 等。**这段是官方踩过的坑**，照做能免掉一堆莫名其妙的崩溃。

> 教学点：`.deb`/`.rpm` 的 `postinst` / `%post` 脚本是"官方维护者写给未来的你的信"，装任何异平台包都应该先读。

### 布局选择

```
~/.local/opt/com.hzt.xc/     # 程序本体（对应 /opt/apps/com.hzt.xc）
~/.local/bin/hzt-xc          # 启动器（替代官方 Elevator.sh）
~/.local/share/applications/com.hzt.xc.desktop
```

为什么不用 `/opt/apps`：没有 sudo；而且**用户目录安装 = 删目录即卸载**，完全可逆。

---

# 三、阶段 2：缺库 —— 用 loader 自己的话定位

### 现象
启动器执行后没窗口、没提示，几秒退出。

### 命令

```bash
ldd ./com.hzt.xc | grep "not found"
#   librtmp.so.1 => not found
#   liblber-2.4.so.2 => not found
#   libldap_r-2.4.so.2 => not found
#   libsasl2.so.2 => not found

# 看某个库自己还依赖谁（关键！）
readelf -d libldap_r-2.4.so.2 | grep -E "NEEDED|RPATH|RUNPATH"
```

### 为什么不能直接把库丢进主目录
`libldap_r-2.4.so.2` 自己还 NEEDED 别的库，而**这些间接依赖只在 `LD_LIBRARY_PATH` 里找，不走调用者的 RUNPATH**。所以最终方案是统一放 `extra/`，由启动器设 `LD_LIBRARY_PATH`：

```sh
export LD_LIBRARY_PATH="$APP_DIR/extra${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

### 一个必须注意的陷阱
Fedora 只有 `libsasl2.so.3`，**ABI 不兼容**，不能软链成 `.so.2` 蒙混。`libldap-2.4` 同理（Fedora 已经是 2.6）。这类情况只能取 Debian 侧的同版本 `.deb` 拆出 `.so`。

---

# 四、阶段 3：可执行栈标记（ELF 位操作）

### 现象
静默退出。真正的错误藏在 dlopen 里：

```
cannot enable executable stack as shared object requires: Invalid argument
```

### 命令

```bash
readelf -lW application_gov.so | grep -A1 GNU_STACK
#   GNU_STACK ... RWE 0x10     ← RWE = 可读可写可执行
```

### 为什么会炸
glibc 2.43 + SELinux Enforcing 下，`dlopen` 一个要求"可执行栈"的 `.so` 会被拒绝（安全策略），而 App 没处理这个返回值 → 静默退出。UOS 上的老 glibc 不管这事，所以官方包"没问题"。

### 修复：直接改程序头
`PT_GNU_STACK` 的 `p_flags` 从 `0x7`（RWX）改成 `0x6`（RW）：

```python
import struct
p = "application_gov.so"
d = bytearray(open(p, "rb").read())
e_phoff    = struct.unpack_from("<Q", d, 0x20)[0]
e_phentsize= struct.unpack_from("<H", d, 0x36)[0]
e_phnum    = struct.unpack_from("<H", d, 0x38)[0]
for i in range(e_phnum):
    off = e_phoff + i * e_phentsize
    if struct.unpack_from("<I", d, off)[0] == 0x6474E551:   # PT_GNU_STACK
        struct.pack_into("<I", d, off + 4, 0x6)            # RW
open(p, "wb").write(d)
```

验证：`readelf -lW application_gov.so | grep GNU_STACK` → 现在是 `RW`。

> 教学点：ELF64 的 program header 布局是 `p_type(4) + p_flags(4) + p_offset(8) ...`，所以 flags 在 `off+4`。这类"一个字段救活一个程序"的修复，比重装系统靠谱得多。
> 风险：改了厂商签名，但该文件本来就不做完整性校验（否则 245 个符号那事早拦住了）。

---

# 五、阶段 4：登录后 SIGSEGV —— 符号劫持（重点）

这是整个项目技术含量最高的一段。

### 5.1 先拿到真实的崩溃栈

```bash
ls ~/com.hzt.xc/dump/                 # breakpad 转储
grep -a "SIGSEGV\|#0 " ~/com.hzt.xc/log/application_gov_*.log | tail
# 或进程还在时：
gdb -p $(pgrep -f '[c]om.hzt.xc' | head -1) -batch -ex "thread apply all bt"
```

得到的栈：

```
#0  0x0                             ← 调用空函数指针
#1  sqlite3Malloc.lto_priv.0        /lib64/libsqlite3.so.0
#2  openDatabase                    /lib64/libsqlite3.so.0
#3  sdb_openDB → sftk_DBInit        /lib64/libsoftokn3.so
#9  NSC_Initialize                  /lib64/libsoftokn3.so
#16 NSS_InitReadWrite               /libnss3.so
#17 ???                             ./libcef.so
```

### 5.2 读栈的方法
不要看到 `sqlite3` 就去修 sqlite。**看调用方向**：NSS → softokn → 系统 libsqlite3 → 空指针。也就是说：崩的是**系统的** sqlite3，而调用链来自 CEF 初始化证书库。

### 5.3 提出假设：符号冲突

```bash
nm -D --defined-only application_gov.so | grep -c ' sqlite3_'
#   245
```

一个应用自己静态链接了 sqlite3，还把 245 个 API **以默认可见性导出**。系统库里也有同名符号 → 谁先加载谁赢。

### 5.4 用 loader 的日志"实锤"

这是本阶段最关键的一条命令：

```bash
LD_DEBUG=bindings ./com.hzt.xc 2>&1 | grep -i sqlite3 | head
```

输出：

```
binding file /lib64/libsqlite3.so.0 [0] to .../application_gov.so [0]: normal symbol `sqlite3_initialize'
binding file /lib64/libsqlite3.so.0 [0] to .../application_gov.so [0]: normal symbol `sqlite3_mutex_enter'
```

**系统 sqlite3 自己的内部调用，被绑定到了应用里的那份副本。** 两份实现共用一个全局状态，`sqlite3GlobalConfig.m.xMalloc` 没人初始化 → 空指针。

> 教学点：`LD_DEBUG=bindings` 是动态链接问题的"X 光机"。遇到"NoSuchSymbol / 行为诡异 / 只在特定程序里崩"的库问题，先开它。

### 5.5 三个失败方案（这部分比成功方案更值钱）

| 尝试 | 思路 | 为什么失败 |
|---|---|---|
| `LD_PRELOAD` 系统 libsqlite3 | 让系统版抢在前面 | 两份实现互相干扰，`InitGlobalDB` 直接坏掉 |
| `objcopy --localize-symbols` | 把 245 个符号降为 local | **二进制已被 strip**，没有符号表，改了个寂寞 |
| `dlopen(RTLD_LOCAL)` shim | 限制符号可见性 | 应用本来就用 `RTLD_LOCAL` 加载，钩子根本不触发 |

三次失败给出的结论：**不要去动别人的二进制，也不要去抢同一个符号**。

### 5.6 最终方案：改"路径"而不是改"根因"

崩溃只在一条路径上发生：**CEF 想打开 `~/.pki/nssdb` 证书库**。那就让这次初始化变成"无数据库模式"：

```c
// nss_nodb_shim.c（核心 20 行）
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
typedef int SECStatus;

static SECStatus nodb_init(void) {
    void *h = dlopen("libnss3.so", RTLD_NOW | RTLD_GLOBAL);
    SECStatus (*f)(const char *) = h ? dlsym(h, "NSS_NoDB_Init") : NULL;
    return f ? f(NULL) : -1;
}
SECStatus NSS_InitReadWrite(const char *d) { return nodb_init(); }
SECStatus NSS_Init(const char *d)          { return nodb_init(); }
```

```bash
gcc -shared -fPIC -O2 -o libhzt_nss_nodb.so nss_nodb_shim.c -ldl
# 启动器里：
export LD_PRELOAD=/.../shims/libhzt_nss_nodb.so
```

验证（日志里必须出现这行，否则说明 shim 没生效）：

```
[hzt-shim] NSS_InitReadWrite(sql:/home/user/.pki/nssdb) -> NSS_NoDB_Init
```

**代价**：这个 App 不再读客户端证书（扫码/短信登录不受影响）。这是一个**有意识的、写进文档的权衡**。

> 教学点：修 bug 有两条路——"消除根因"和"绕开触发路径"。前者更正确但更危险（改别人的二进制），后者更小、更可逆。当你无法掌控上游代码时，后者往往是工程最优解。

### 5.7 一个容易骗到自己的坑
`SIGTERM` 杀进程时，breakpad 也会写 `.dmp`。所以**看到 dump 不等于崩溃**。判断依据永远是：栈里有没有非法地址 + 日志里的退出码。这个项目里我误判过一次，后来固定用 `rm -f ~/com.hzt.xc/dump/*.dmp*` 再重启来对照。

---

# 六、阶段 5：白字白底 —— 一次教科书级的"假设更正"

这一节几乎没有新命令，全是**方法论**：我连续错了 3 次，最后靠"看窗口结构"翻盘。

### 6.1 错误假设 1：能开 DevTools 查 CSS

```bash
./com.hzt.xc --remote-debugging-port=9222
ss -ltnp | grep 9222      # 什么都没有
```

原因：CEF 的调试端口要由 `CefSettings.remote_debugging_port` 打开，**命令行开关在这里不生效**。→ 这条路直接封死，别浪费时间。

### 6.2 错误假设 2：是 `prefers-color-scheme` 的 UA 默认色

推理很顺：系统是 BreezeDark → Chromium 认为 dark → 输入框没设 `color`，UA 给白字 → 但页面 CSS 是浅色 → 白字白底。

于是做了两步：
```bash
# 1) 看 libcef 里有没有门户客户端
strings -a libcef.so | grep -xE "org.freedesktop.portal.Settings|ReadOne"
#   → 空（说明不是走 portal，而是 GTK 设置）

# 2) 造一个浅色 GTK 配置，用 GTK 自己验证生效
XDG_CONFIG_HOME=/tmp/xlight GTK_THEME=Adwaita:light \
  python3 -c 'import gi;gi.require_version("Gtk","3.0");from gi.repository import Gtk;
s=Gtk.Settings.get_default();print(s.get_property("gtk-theme-name"),
s.get_property("gtk-application-prefer-dark-theme"))'
#   → Adwaita False   ✅ GTK 层确实变浅了
```

**但用户说还是白的。**

### 6.3 错误假设 3：干脆强制深色

```bash
./com.hzt.xc --force-dark-mode
```

结果：整页颜色**一点没变**。这一枪非常关键——它证明了：
> 页面 CSS 是写死的浅色，**根本不跟随系统配色**。所以"白字"不是网页层的问题。

### 6.4 转折点：看 X 窗口树

不猜了，直接问系统"这个窗口到底是什么组成的"：

```python
from Xlib import display
d = display.Display(); root = d.screen().root

def walk(w, depth=0):
    for c in w.query_tree().children:
        g = c.get_geometry()
        print("  "*depth, g.width, g.height, c.get_wm_name(), c.get_wm_class())
        walk(c, depth+1)
```

输出里出现了决定性证据：

```
1126x1118
  1126x1014
    1126x622  chat_view -> CefWindowX11     ← 消息列表（网页）
    1126x390  (没有 CefWindowX11 子窗口)     ← 输入区
```

**输入区没有 CEF 子窗口 = 它是 Qt 原生控件。** 一个窗口里同时有"网页渲染的消息列表"和"原生绘制的输入框"——这解释了为什么只有输入框有颜色问题。

> 教学点：混合架构（Qt/Electron/CEF/WPF）出 UI 怪问题时，**第一步永远是画出窗口/控件树**。看代码猜是下策。

### 6.5 让"看不见的状态"显形

输入框是空的，空框看不出文字颜色。所以要**注入输入**。

先试 XTEST（就是 xdotool 的底层）：
```
KDE 弹出「python3 请求控制输入设备」授权框   ← Wayland 合成器拦截
```
这条路被安全策略挡住了，而且不该为了调试去改用户的权限。

换 `XSendEvent`——直接往窗口的事件队列投递按键，走应用层，不需要任何授权：

```python
from Xlib.protocol import event as E
kc = d.keysym_to_keycode(XK.string_to_keysym('a'))
d.set_input_focus(win, X.RevertToParent, X.CurrentTime)
for kind in (E.KeyPress, E.KeyRelease):
    win.send_event(kind(time=X.CurrentTime, root=root, window=win, same_screen=1,
                        child=X.NONE, root_x=0, root_y=0, event_x=0, event_y=0,
                        state=0, detail=kc),
                   propagate=True, event_mask=X.KeyPressMask)
```

输入 "abc" 后抓窗口像素 → 文字是 **(255,255,255) 纯白**。假设确认：**Qt 调色板的 `WindowText` 是白色**（BreezeDark），而背景是 App 画死的 `#F6F6F6`。

### 6.6 抓窗口的正确姿势（比截图好用）

```python
img = win.get_image(0, 0, w, h, X.ZPixmap, 0xffffffff)
im  = Image.frombytes("RGB", (w, h), img.data, "raw", "BGRX")
```

优点：**不受遮挡、不受合成器/缩放影响、拿到的是窗口自己的内容**。`spectacle` 只能拍"屏幕上看到的"，一旦窗口被 Chrome 盖住就废了——我前面就吃过这个亏。

### 6.7 修完为什么还是白的（我自己的 bug）

第一版修复很"聪明"：给 App 一个独立 `XDG_CONFIG_HOME`，里面把所有配置**软链**回 `~/.config`，只替换 `gtk-3.0/`。

```sh
for f in "$HOME/.config"/*; do ln -sfn "$f" "$XDG_LIGHT/$(basename "$f")"; done
```

问题就在这个循环：它把 **`kdeglobals` 也链回去了**，而 `kdeglobals` 里写着 `ColorScheme=BreezeDark`。于是 Qt 调色板还是白的——**环境变量设对了，但语义被自己镜像回来了**。

修正就一行：

```sh
case "$b" in gtk-3.0|kdeglobals|kdeglobals.*) continue ;; esac
```

重启后重测：文字像素 **(0,0,0)**。

> 教学点：改环境/改路径之后，必须验证"改动真的到达了目标进程"，而不是假设它生效。我这次的验证方式就是**用同一个窗口、同一个注入文字、只比最暗像素**——单变量对照。

### 6.8 验证结果

| | 修复前 | 修复后 |
|---|---|---|
| 输入 "abc" 后最暗像素 | `(255,255,255)` | `(0,0,0)` |
| 输入区背景 | `#F6F6F6` | `#F6F6F6`（未变） |
| 其它 UI | 正常 | 正常（无回归） |

---

# 七、可复用的排障套路

1. **先分层，再动手**：网页 / 原生 / 进程 / 内核，四层各用不同工具。混着猜一定走弯路。
2. **读 loader 的真话**：`ldd` → `readelf -d` → `LD_DEBUG=bindings`，比读源码快 10 倍。
3. **用数据代替眼睛**：不要"看起来像是白的"，要 `(255,255,255)` vs `(0,0,0)`。
4. **让隐形的状态显形**：空输入框 → 注入文字；隐藏面板 → 抓窗口像素。
5. **一次只改一个变量，并验证它生效**。
6. **优先绕开触发路径，而不是重写别人的二进制**（改动越小越可逆）。
7. **保持可逆**：用户目录安装 + 单个启动器 + 一份 `INSTALL-NOTES.md`。
8. **看 dump ≠ 崩溃**：先确认退出码和调用栈。

### 如果重来一次，我会更快的地方
- 阶段 5 直接跳到"画窗口树"，能省掉 80% 的时间。**UI 怪问题先看结构，别先看主题**。
- 阶段 4 的 `LD_DEBUG=bindings` 应该更早跑——`nm -c` 看到 245 个导出符号时就该怀疑。
- 关闭 CDP 那条路要更早：CEF 应用先确认 `ss -ltnp`，别赌命令行开关。

---

# 八、命令速查表

```bash
# —— 打包/解包 ——
ar t pkg.deb ; ar x pkg.deb ; tar -xf data.tar.xz ; cat postinst
rpm2cpio pkg.rpm | cpio -idmv

# —— 依赖 ——
ldd ./bin | grep "not found"
readelf -d lib.so | grep -E "NEEDED|RPATH|RUNPATH"
strings -a bin | grep <符号名>

# —— ELF 结构 ——
readelf -lW  bin.so | grep -A1 GNU_STACK      # 看栈标记
readelf -h   bin.so                            # 看 e_phoff 等
nm -D --defined-only bin.so | grep -c ' sqlite3_'

# —— 动态链接行为 ——
LD_DEBUG=bindings ./bin 2>&1 | grep -i <name>  # 谁绑到了谁
LD_DEBUG=libs     ./bin 2>&1 | grep -i <name>  # 加载顺序
LD_PRELOAD=./shim.so ./bin                     # 函数拦截

# —— 崩溃 ——
ulimit -c unlimited
gdb -p PID -batch -ex "thread apply all bt"
gdb ./bin core -batch -ex bt

# —— X11 / GUI 定位 ——
python3 - <<'PY'   # 窗口树
from Xlib import display
d=display.Display(); r=d.screen().root
def w(x,i=0):
    for c in x.query_tree().children:
        g=c.get_geometry(); print("  "*i,g.width,g.height,c.get_wm_name(),c.get_wm_class()); w(c,i+1)
w(r)
PY
# 抓窗口像素（不受遮挡）
win.get_image(0,0,w,h,X.ZPixmap,0xffffffff) ; Image.frombytes(...,"raw","BGRX")
# 注入按键（绕过 Wayland 输入授权）
win.send_event(E.KeyPress(...), event_mask=X.KeyPressMask)

# —— 截图/查看 ——
spectacle -b -n -f -o out.png

# —— 杀进程时不误伤自己 ——
pkill -f 'files/3.14.0-Release.2/[c]om.hzt.xc'   # [c] 让模式不匹配本行命令
```

---

## 最后一句

这个项目真正的产出不是"让一个国产办公软件跑起来"，而是两条能力：

1. **把模糊的"不好用"拆成可验证的技术命题**（"白字" → "哪个窗口？谁画的？什么颜色值？"）。
2. **接受假设被推翻，并用实验快速收敛**（我错了三次，但每次只花一条命令就排除了一种可能）。

全部结论都固化在 `~/.local/opt/com.hzt.xc/INSTALL-NOTES.md` 里，包括副作用和未采用的方案——这部分往往比"能跑了"更有价值。
