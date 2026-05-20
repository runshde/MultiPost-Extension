#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================"
echo "  MultiPost 本地隐私版 - 同步上游更新脚本"
echo "================================================"
echo ""

# ── 1. 确保 upstream remote 存在 ──────────────────
if ! git remote | grep -q "upstream"; then
  echo "📌 添加上游仓库..."
  git remote add upstream https://github.com/leaperone/MultiPost-Extension.git
fi

# ── 2. 拉取上游最新代码 ───────────────────────────
echo "📥 获取上游最新代码..."
git fetch upstream

# ── 3. 检查是否有更新 ─────────────────────────────
UPSTREAM_COMMITS=$(git rev-list HEAD..upstream/main --count)
if [ "$UPSTREAM_COMMITS" = "0" ]; then
  echo ""
  echo "✅ 已经是最新版本，无需更新。"
  exit 0
fi

echo ""
echo "📋 上游有 $UPSTREAM_COMMITS 个新提交："
git log HEAD..upstream/main --oneline
echo ""

# ── 4. 备份我们的隐私修改文件 ─────────────────────
echo "💾 备份隐私修改..."
mkdir -p .privacy-patch

cp src/popup/index.tsx           .privacy-patch/popup.tsx
cp src/options/index.tsx         .privacy-patch/options.tsx
cp src/background/index.ts       .privacy-patch/background.ts
cp src/background/services/api.ts .privacy-patch/api.ts
cp src/sync/account.ts           .privacy-patch/account.ts
cp src/sync/extraconfig.ts       .privacy-patch/extraconfig.ts
cp src/tabs/publish.tsx          .privacy-patch/publish.tsx

# ── 5. 合并上游更新 ───────────────────────────────
echo "🔄 合并上游更新..."

# 合并时，我们修改过的7个文件如有冲突，优先取上游版本（之后我们再重新打补丁）
git merge upstream/main \
  -X ours \
  --no-edit \
  -m "chore: sync upstream $(git rev-parse --short upstream/main)" \
  2>&1 || {
    echo ""
    echo "⚠️  合并有冲突，正在自动处理..."
    git checkout --theirs \
      src/popup/index.tsx \
      src/options/index.tsx \
      src/background/index.ts \
      src/background/services/api.ts \
      src/sync/account.ts \
      src/sync/extraconfig.ts \
      src/tabs/publish.tsx 2>/dev/null || true
    git add -A
    git commit --no-edit -m "chore: sync upstream with conflict resolution" || true
  }

# ── 6. 恢复/重打隐私补丁 ─────────────────────────
echo "🔒 重新应用隐私补丁..."

# popup: 打开本地 options 页而非 multipost.app
POPUP_SRC=$(cat src/popup/index.tsx)
if echo "$POPUP_SRC" | grep -q "multipost.app"; then
  cp .privacy-patch/popup.tsx src/popup/index.tsx
  echo "  ✓ popup/index.tsx"
fi

# options: 完整本地 UI（我们的版本是完全重写）
OPTIONS_SRC=$(cat src/options/index.tsx)
if echo "$OPTIONS_SRC" | grep -q "multipost.app"; then
  cp .privacy-patch/options.tsx src/options/index.tsx
  echo "  ✓ options/index.tsx"
fi

# background/index.ts: 删除云端 ping 启动 & 安装跳转
BG_SRC=$(cat src/background/index.ts)
if echo "$BG_SRC" | grep -q "multipost.app/on-install"; then
  sed -i 's|chrome.tabs.create({ url: "https://multipost.app/on-install" });|chrome.runtime.openOptionsPage();|g' \
    src/background/index.ts
  echo "  ✓ background/index.ts (on-install redirect)"
fi
if echo "$BG_SRC" | grep -q "starter("; then
  sed -i 's|starter(1000 \* 30);|// Cloud ping removed — fully local mode|g' \
    src/background/index.ts
  echo "  ✓ background/index.ts (cloud ping)"
fi
# 同步 import：如果 starter 又被加回来了则移除
if grep -q "starter" src/background/index.ts; then
  sed -i 's|import { linkExtensionMessageHandler, starter } from "./services/api";|import { linkExtensionMessageHandler } from "./services/api";|g' \
    src/background/index.ts
fi

# api.ts: 删除所有云端请求（保留 linkExtension 本地通信）
API_SRC=$(cat src/background/services/api.ts)
if echo "$API_SRC" | grep -q "multipost.app"; then
  cp .privacy-patch/api.ts src/background/services/api.ts
  echo "  ✓ background/services/api.ts"
fi

# account.ts: 删除 ping import 和调用
if grep -q "import { ping }" src/sync/account.ts; then
  sed -i '/import { ping } from "~background\/services\/api";/d' src/sync/account.ts
  sed -i '/await ping(true);/d' src/sync/account.ts
  echo "  ✓ sync/account.ts"
fi

# extraconfig.ts: 删除 ping import 和调用
if grep -q "import { ping }" src/sync/extraconfig.ts; then
  sed -i '/import { ping } from "~background\/services\/api";/d' src/sync/extraconfig.ts
  sed -i '/await ping(true);/d' src/sync/extraconfig.ts
  echo "  ✓ sync/extraconfig.ts"
fi

# publish.tsx: 删除 multipost.app 联系链接
if grep -q "docs.multipost.app" src/tabs/publish.tsx; then
  # 删除 Contact us footer 块
  python3 - <<'PYEOF'
import re
with open("src/tabs/publish.tsx", "r") as f:
    content = f.read()
pattern = r'\s*\{/\* Contact us footer tip \*/\}.*?</div>\s*(?=\s*</div>)'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open("src/tabs/publish.tsx", "w") as f:
    f.write(content)
PYEOF
  echo "  ✓ tabs/publish.tsx"
fi

# ── 7. 提交补丁 ───────────────────────────────────
echo ""
CHANGED=$(git diff --name-only)
if [ -n "$CHANGED" ]; then
  git add src/popup/index.tsx src/options/index.tsx src/background/index.ts \
          src/background/services/api.ts src/sync/account.ts \
          src/sync/extraconfig.ts src/tabs/publish.tsx 2>/dev/null || true
  git diff --cached --quiet || \
    git commit -m "fix: reapply privacy patches after upstream sync"
fi

# ── 8. 推送到自己的 fork ──────────────────────────
echo ""
echo "📤 推送到 GitHub..."
git push origin main --force-with-lease

# ── 9. 安装依赖 & 构建 ────────────────────────────
echo ""
echo "📦 安装依赖..."
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

echo ""
echo "🔨 构建插件..."
pnpm build

# ── 10. 完成 ──────────────────────────────────────
echo ""
echo "================================================"
echo "  ✅ 同步完成！"
echo "================================================"
echo ""
echo "  📦 zip 包：build/chrome-mv3-prod.zip"
echo "  📁 解压包：build/chrome-mv3-prod/"
echo ""
echo "  Chrome 安装方法："
echo "  chrome://extensions → 开发者模式 → 加载已解压 → 选 build/chrome-mv3-prod/"
echo ""
