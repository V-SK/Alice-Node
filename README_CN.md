# Alice Node

[English →](README.md)

**一个仓库，三种角色，一行命令。**

Alice Node 是 [Alice Protocol](https://aliceprotocol.org) 的统一客户端 —— 去中心化 AI 训练网络。挖矿、验证、聚合，全部统一入口。

```bash
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node && ./install.sh
python alice_node.py mine
```

## 三种角色

### ⛏️ 挖矿 (Mine)
训练 Alice 神经网络，按梯度质量获得 ALICE 代币奖励。

```bash
python alice_node.py mine --gpus all
```

**要求:** 24GB+ 显存 (NVIDIA) 或 24GB+ 统一内存 (Apple Silicon)

### 🛡️ 验证 (Score)
运行评分服务器，独立验证矿工提交的梯度。

```bash
python alice_node.py score --model-path ./model.pt --device cpu
```

**要求:** 32GB+ 内存，质押 5,000 ALICE

### 🔗 聚合 (Aggregate)
运行聚合节点 —— 收集、聚合矿工梯度并转发到参数服务器。

```bash
python alice_node.py aggregate --ps-url https://ps.aliceprotocol.org
```

**要求:** 16GB+ 内存，高速网络，质押 10,000 ALICE

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/V-SK/Alice-Node.git
cd Alice-Node

# 2. 安装（自动检测 GPU，创建虚拟环境）
./install.sh

# 3. 创建钱包
python alice_node.py wallet create

# 4. 开始挖矿
python alice_node.py mine
```

## 命令参考

| 命令 | 说明 |
|------|------|
| `alice-node mine` | 开始挖矿 |
| `alice-node score` | 运行评分服务器 |
| `alice-node aggregate` | 运行聚合节点 |
| `alice-node stake --role scorer --amount 5000` | 质押为验证者 |
| `alice-node stake --role aggregator --amount 10000` | 质押为聚合者 |
| `alice-node unstake --role scorer` | 取消质押 |
| `alice-node status` | 查看网络状态 |
| `alice-node wallet create` | 创建钱包 |
| `alice-node wallet import` | 导入钱包 |
| `alice-node wallet balance` | 查看余额 |

## 硬件要求

| 角色 | GPU 显存 | 系统内存 | 磁盘 | 网络 | ALICE 质押 |
|------|----------|----------|------|------|-----------|
| **矿工** | 24 GB+ | 16 GB | 20 GB | 10 Mbps | — |
| **验证者** | 可选 | 32 GB+ | 20 GB | 50 Mbps | 5,000 |
| **聚合者** | — | 16 GB+ | 50 GB | 100 Mbps | 10,000 |

## 奖励

- **总供应量:** 21,000,000 ALICE（固定，永不增发）
- **年 1-2 预算:** 5,250,000 ALICE/年，每 2 年减半
- **每轮奖励:** ~600 ALICE（每轮约 60 分钟）
- **矿工份额:** 56-90%（动态）
- **基础设施:** 9%（验证者 5% + 聚合者 2% + 调度器 2%）

## 从 Alice-Miner 升级

旧的 `Alice-Miner` 仓库已重命名为 `Alice-Node`：

1. GitHub 自动重定向 `V-SK/Alice-Miner` → `V-SK/Alice-Node`
2. 根目录的 `alice_miner.py` 仍然可用（会显示弃用提示）
3. `start_mining.sh` 无需修改
4. `~/.alice/wallet.json` 钱包完全兼容

**建议:** 使用 `python alice_node.py mine` 新的统一 CLI。

## 链接

- **官网:** [aliceprotocol.org](https://aliceprotocol.org)
- **白皮书:** [dl.aliceprotocol.org/whitepaper](https://dl.aliceprotocol.org/whitepaper)
- **PS 状态:** [ps.aliceprotocol.org/status](https://ps.aliceprotocol.org/status)
- **Twitter:** [@Alice_AI102](https://twitter.com/Alice_AI102)

## 协议

MIT
