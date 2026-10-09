# BEM 任务托管（合约代码名 GrantEscrow）

> 钱先锁，活干完，验收即结算。
>
> ⚠️ 当前是 **BSC 测试网演示**，代币是测试 BEM，没有价值。合约**还没审计**，没有部署到主网。

- 在线演示：https://renyuefeng1-dot.github.io/bem-grants/
- 测试网合约：`0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF`  https://testnet.bscscan.com/address/0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF
- 测试网 MockBEM（8 位小数，任何人可 mint）：`0xAf81078FA7DF6aF5E5bD97B98a358939600EC320`
- 主网 BEM（上主网时使用）：`0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a`

## 一、为什么做

项目方找人干活，怕钱付了活没干好；接单的人也怕干完拿不到钱。现在大多靠口头约定、私信转账，钱到没到、给了谁、什么时候给的，外人都查不到。

这个工具把结算搬到链上：**钱先锁进合约 → 公开接单 → 验收人选定接单人 → 交付后验收人确认、合约自动结算**。谁也赖不了账，每一步都有事件，BscScan 上可查。

> 说明：合约和函数名沿用最初的代码名（`GrantEscrow`、`createMilestone`、`voteRelease` 等），合约本身没有改动；页面和文档改用「任务 / 接单 / 验收 / 结算」的叫法。对应关系：Pool = 任务池，funder = 发布方，approver = 验收人，milestone = 任务 / 阶段，applicant / recipient = 接单人，release = 结算。

## 二、怎么运作

1. **发布方**（项目方、团队、个人）调用 `createPool` 创建任务池：存入 BEM，写上标题/说明，指定 N 个验收人和门槛 M（例如 2-of-3），设置结算销毁比例（默认 1%，最高 10%）。
2. **任何人**都可以 `topUp` 给任务池追加 BEM。
3. 发布方或验收人用 `createMilestone` 从“未分配余额”里划出一个**任务**（或阶段）：金额、接单截止时间、说明 / 验收标准；可以直接指定接单人（定向派单），也可以留空开放接单。划出后这笔钱变成“已分配”。
4. 想干活的人调用 `applyFor` 提交**接单申请**（方案 / 作品链接写在链上）。
5. 验收人 `voteAward` 投票，某个接单申请拿到 **M 票**后自动成为接单人（投票可以改投）。
6. 接单人交付后 `submitDelivery` 提交链接。
7. 验收人验收通过后 `voteRelease`，达到 **M 票**时合约立刻结算：`金额 × 销毁比例` 转入 `0x000000000000000000000000000000000000dEaD`，其余打给接单人。
8. 不需要的任务：验收人 `voteCancel`，M 票后资金退回任务池；没人接且过了接单截止的，任何人都能 `expire`；接单人也可以 `relinquish` 主动放弃。
9. 发布方想撤回资金：`requestWithdraw` 先在链上公示 **7 天**，期满后 `executeWithdraw`，而且只能取回**未分配**的部分。

## 三、谁能做什么

| 角色 | 能做 | 不能做 |
|---|---|---|
| 验收人（M-of-N） | 选定接单人、验收结算、取消未结算的任务——每项都要 M 票 | 把钱转给自己或接单人以外的地址；单个验收人什么都做不了；不能改验收人名单 |
| 发布方 | 创建任务；取回**未分配**余额（须提前 7 天公示，可撤销） | 动用已分配给任务的资金；绕过公示期；单方面取消任务 |
| 接单人 | 提交交付链接、主动放弃 | 自己给自己结算 |
| 任何人 | 追加资金、接单、把过期的开放任务退回任务池 | —— |
| 合约部署者 / 平台 | **没有任何权限**：没有 owner、不可升级、没有管理员提款函数 | —— |

要注意的风险：
- 验收人如果有 M 个串通，可以把任务派给自己人并结算。所以验收人要选不同利益方（比如发布方 1 人 + 社区 2 人），并公开身份。
- 验收人如果失联超过 N-M 个，已选定接单人的任务会卡住（只有接单人主动放弃才能退回）。所以门槛不要设成 N-of-N，验收人最好用多签或硬件钱包。
- 验收人名单创建后不能改；要换人只能新建任务池（把未分配资金按 7 天公示取回后转过去）。
- 合约拒绝“转账扣手续费”的代币（到账 ≠ 转账金额会直接回滚）。真实 BEM 是标准 ERC20，上主网前会再确认一次。

安全措施：OpenZeppelin `SafeERC20` + `ReentrancyGuard`、先改状态再转账、Solidity 0.8.24 溢出检查、自定义错误、所有操作都有事件。

## 四、测试

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 foundry-rs/forge-std   # 仓库不含 lib/
forge test -vv
```

40 个测试全部通过（含 2 个模糊测试，各 512 轮）：正常流程（1000 BEM、2-of-3、1% 销毁）、定向派单、1-of-1 / 3-of-3 门槛、改投、重复投票、非验收人 / 其他池验收人、重复结算、取消（开放/已选定）、发布方无法动已分配资金、过期、放弃、7 天时间锁（边界秒数、重新申请重置计时、执行时按剩余可用额封顶）、8 位小数销毁取整（1.23456789 BEM → 销毁 0.01234567）、极小金额不销毁、0% 和 10% 销毁、追加资金、拒绝转账收费代币、恶意代币重入（结算 / 取回）、多池隔离、分页视图、资金守恒。

## 五、测试网实跑记录（BSC Testnet，chainId 97）

部署者 `0x6Dc951a2fa02B48A4B91e7aD0c7D23666c9f99e4`（发布方）；3 个验收人和 1 个接单人是本地临时生成的测试钱包。脚本：`deploy/testnet_flow.sh`。

| 步骤 | 交易 |
|---|---|
| 部署 GrantEscrow | https://testnet.bscscan.com/tx/0xd5628c87583172a468cc5246b991445e80a76286c76cde4b52b3abd729952b4d |
| 创建任务池 1000 BEM，2-of-3，销毁 1% | https://testnet.bscscan.com/tx/0xa5cd28128bcbc532c7dd32a33a1dbc8909df3ed0e0eb48bf8076cde47dbe3ec2 |
| 任务 #1 300 BEM | https://testnet.bscscan.com/tx/0x47dbbe2c1448a8dd61155e2fc4a6aa1c30947e61d16b086441282f2377849604 |
| 接单人申请任务 #1 | https://testnet.bscscan.com/tx/0x6873f725af37ca43cedffc226d7a9415adb08d8cb514e970df90af0e78ce18ea |
| 验收人 1、2 投票选定 | https://testnet.bscscan.com/tx/0x4f371273145debde3af3863f0ebaa08277d70104a2fa7f63abe359ff8628f965 · https://testnet.bscscan.com/tx/0x51d90196bd80b7f1ec7ec1b72b26f4920c497146e94182e687ea6ecaf8f5e8cb |
| 提交交付 | https://testnet.bscscan.com/tx/0x099178f6e6e2aa211ed4e19601f5707f0aa006472329a8d3e5dafe63f9a61e17 |
| 验收人 1 验收通过 | https://testnet.bscscan.com/tx/0x197f54247bbbb270890b07ff7a41981e1ee288e44f2db818e1ef27be9d09518e |
| 验收人 3 验收通过 → 结算 297 BEM，销毁 3 BEM | https://testnet.bscscan.com/tx/0xbed7c97d654699379cddcf87a77508d9d01aff9ce8c403292d7108176691931b |
| 任务 #2 200 BEM（演示取消） | https://testnet.bscscan.com/tx/0xddd3a160ecc582f8fa5e25c4791d68695db875584c1409ab0a8c9edef400e2fb |
| 验收人 2、3 投票取消任务 #2 → 200 BEM 退回任务池 | https://testnet.bscscan.com/tx/0x8192dcb968651386891c8b8058d137d46975d48d1c66c1f5e7f68e208d32b660 · https://testnet.bscscan.com/tx/0x402851f6652c335594050b786b15ac194f3cf9abbb3a81b61452ea681fbcd5f5 |
| 任务 #3 100 BEM（保持开放，供演示接单） | https://testnet.bscscan.com/tx/0x4fb9144800a75eeceeb50f7defea10c106322c2f826d0ddb709590ad26a9fe97 |

结果核对：接单人收到 **297 BEM**，`0x…dEaD` 增加 **3 BEM**（正好 1%）；合约余额 700 BEM = 未分配 600 + 任务 #3 已分配 100；`totalPaid=297`，`totalBurned=3`。

## 六、前端

- `frontend/` 纯静态页面，ethers v6 本地加载（`ethers.umd.min.js`，不依赖 CDN），可以直接放进 TapeOut 容器或 GitHub Pages。
- 中文优先，右上角 **中 / EN** 切换（记住选择）；手机优先布局；顶部红色横幅「测试网演示」。
- 页面：任务池列表（托管中 / 已结算 / 已销毁）、任务池详情（任务、接单申请、票数、链上记录，全部链接到 BscScan，原始网址直接显示）、创建任务池、接单、验收人面板（选定 / 结算 / 取消）、发布方面板（新建任务、7 天公示取回）、接单人操作、我的面板。
- 测试网早期写入链上的演示标题用的是旧叫法，`frontend/config.js` 里的 `labelOverrides` 只改页面上的显示名，不改链上数据。
- 钱包：注入式钱包（TokenPocket / MetaMask 内置浏览器），自动切换 / 添加网络。测试网页面有“领取 1000 测试 BEM”按钮。
- 网络配置在 `frontend/config.js`：`active: "bscTestnet"` 改为 `"bsc"` 并填入主网合约地址即可切到主网。

## 七、上主网需要做的

1. **轻量审计**：至少找 1~2 位熟悉 Solidity 的人做 audit-lite 复核（合约约 400 行，没有外部依赖，只用 OpenZeppelin），再跑一遍 Slither。重点看：多签计票、时间锁、结算/取消的资金记账。
2. **确认真实 BEM 是标准 ERC20**（不扣转账手续费、没有黑名单 / 暂停之类会卡住结算的逻辑）。
3. **验收人用多签钱包**：推荐 **Safe（https://app.safe.global ，支持 BNB Chain）**。每个验收人地址最好本身就是一个 Safe 或硬件钱包；发布方地址也建议用 Safe。
4. **主网部署**：用一个只放少量 BNB 的新钱包部署（构造参数只有 BEM 地址），在 BscScan 上验证并开源源码。部署后合约没有任何管理权限，部署钱包之后用不到。
5. 改 `frontend/config.js` 切到主网，去掉测试网横幅；先用小额（比如 50 BEM）建一个真实任务池走一遍，再放大额。

## 八、可以直接发的推文

```
项目方怕付了钱活没干好，接单的怕干完拿不到钱。

我做了个「BEM 任务托管」：BEM 先锁进合约，交付后 3 个验收人里 2 个确认，合约自动结算，谁也赖不了账，每笔都能在 BscScan 查。

https://renyuefeng1-dot.github.io/bem-grants/
测试网演示
```
（加权字数 207 / 280）
