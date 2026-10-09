# TapeOut 生态资助托管板（GrantEscrow）

> ⚠️ 当前是 **BSC 测试网演示**，代币是测试 BEM，没有价值。合约**还没审计**，没有部署到主网。

- 在线演示：https://renyuefeng1-dot.github.io/bem-grants/
- 测试网合约：`0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF`  https://testnet.bscscan.com/address/0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF
- 测试网 MockBEM（8 位小数，任何人可 mint）：`0xAf81078FA7DF6aF5E5bD97B98a358939600EC320`
- 主网 BEM（上主网时使用）：`0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a`

## 一、为什么做

社区基金在成形（创始人认捐 700 BEM 支持 BruceBlue 提议的社区基金、Siman Labs 的 2 万美元基金），但现在是“推文认捐、私信发钱”：钱有没有到位、发给了谁、什么时候发的，外人都查不到。

这个托管板把流程搬到链上：**钱先锁进合约 → 公开申请 → 多签选人 → 交付后多签放款**，每一步都有事件，BscScan 上可查。

## 二、怎么运作

1. **资助方**（基金会、项目方、个人）调用 `createPool` 创建资助池：存入 BEM，写上标题/说明，指定 N 个审批人和门槛 M（例如 2-of-3），设置放款销毁比例（默认 1%，最高 10%）。
2. **任何人**都可以 `topUp` 给资助池追加 BEM。
3. 资助方或审批人用 `createMilestone` 从“未分配余额”里划出一个**里程碑**：金额、申请截止时间、说明；可以直接指定受助人（定向资助），也可以留空开放申请。划出后这笔钱变成“已分配”。
4. **开发者**调用 `applyFor` 提交申请（方案/作品链接写在链上）。
5. 审批人 `voteAward` 投票，某个申请拿到 **M 票**后自动成为受助人（投票可以改投）。
6. 受助人交付后 `submitDelivery` 提交链接。
7. 审批人 `voteRelease`，达到 **M 票**时合约立刻放款：`金额 × 销毁比例` 转入 `0x000000000000000000000000000000000000dEaD`，其余打给受助人。
8. 不需要的里程碑：审批人 `voteCancel`，M 票后资金退回资金池；无人获选且过了申请截止的，任何人都能 `expire`；受助人也可以 `relinquish` 主动放弃。
9. 资助方想撤资：`requestWithdraw` 先在链上公示 **7 天**，期满后 `executeWithdraw`，而且只能取回**未分配**的部分。

## 三、信任模型

| 角色 | 能做 | 不能做 |
|---|---|---|
| 审批人（M-of-N） | 选定受助人、同意放款、取消未放款的里程碑——每项都要 M 票 | 把钱转给自己或任何非受助人地址；单个审批人什么都做不了；不能改审批人名单 |
| 资助方 | 创建里程碑；取回**未分配**余额（须提前 7 天公示，可撤销） | 动用已分配给里程碑的资金；绕过公示期；取消里程碑 |
| 受助人 | 提交交付链接、自愿放弃 | 自己给自己放款 |
| 任何人 | 追加资金、申请、把过期的开放里程碑退回资金池 | —— |
| 合约部署者 / 平台 | **没有任何权限**：没有 owner、不可升级、没有管理员提款函数 | —— |

要注意的风险：
- 审批人如果有 M 个串通，可以把里程碑选给自己人并放款。所以审批人要选不同利益方（比如基金方 1 人 + 社区 2 人），并公开身份。
- 审批人如果失联超过 N-M 个，已选定的里程碑会卡住（只有受助人自愿放弃才能退回）。所以门槛不要设成 N-of-N，审批人最好用多签或硬件钱包。
- 审批人名单创建后不能改；要换人只能新建资助池（把未分配资金按 7 天公示取回后转过去）。
- 合约拒绝“转账扣手续费”的代币（到账 ≠ 转账金额会直接回滚）。真实 BEM 是标准 ERC20，上主网前会再确认一次。

安全措施：OpenZeppelin `SafeERC20` + `ReentrancyGuard`、先改状态再转账、Solidity 0.8.24 溢出检查、自定义错误、所有操作都有事件。

## 四、测试

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 foundry-rs/forge-std   # 仓库不含 lib/
forge test -vv
```

40 个测试全部通过（含 2 个模糊测试，各 512 轮）：正常流程（1000 BEM、2-of-3、1% 销毁）、定向资助、1-of-1 / 3-of-3 门槛、改投、重复投票、非审批人 / 其他池审批人、重复放款、取消（开放/已选定）、资助方无法动已分配资金、过期、放弃、7 天时间锁（边界秒数、重新申请重置计时、执行时按剩余可用额封顶）、8 位小数销毁取整（1.23456789 BEM → 销毁 0.01234567）、极小金额不销毁、0% 和 10% 销毁、追加资金、拒绝转账收费代币、恶意代币重入（放款 / 取回）、多池隔离、分页视图、资金守恒。

## 五、测试网实跑记录（BSC Testnet，chainId 97）

部署者 `0x6Dc951a2fa02B48A4B91e7aD0c7D23666c9f99e4`（资助方）；3 个审批人和 1 个开发者是本地临时生成的测试钱包。脚本：`deploy/testnet_flow.sh`。

| 步骤 | 交易 |
|---|---|
| 部署 GrantEscrow | https://testnet.bscscan.com/tx/0xd5628c87583172a468cc5246b991445e80a76286c76cde4b52b3abd729952b4d |
| 创建资助池 1000 BEM，2-of-3，销毁 1% | https://testnet.bscscan.com/tx/0xa5cd28128bcbc532c7dd32a33a1dbc8909df3ed0e0eb48bf8076cde47dbe3ec2 |
| 里程碑 M1 300 BEM | https://testnet.bscscan.com/tx/0x47dbbe2c1448a8dd61155e2fc4a6aa1c30947e61d16b086441282f2377849604 |
| 开发者申请 M1 | https://testnet.bscscan.com/tx/0x6873f725af37ca43cedffc226d7a9415adb08d8cb514e970df90af0e78ce18ea |
| 审批人 1、2 投票选定 | https://testnet.bscscan.com/tx/0x4f371273145debde3af3863f0ebaa08277d70104a2fa7f63abe359ff8628f965 · https://testnet.bscscan.com/tx/0x51d90196bd80b7f1ec7ec1b72b26f4920c497146e94182e687ea6ecaf8f5e8cb |
| 提交交付 | https://testnet.bscscan.com/tx/0x099178f6e6e2aa211ed4e19601f5707f0aa006472329a8d3e5dafe63f9a61e17 |
| 审批人 1 同意放款 | https://testnet.bscscan.com/tx/0x197f54247bbbb270890b07ff7a41981e1ee288e44f2db818e1ef27be9d09518e |
| 审批人 3 同意放款 → 放款 297 BEM，销毁 3 BEM | https://testnet.bscscan.com/tx/0xbed7c97d654699379cddcf87a77508d9d01aff9ce8c403292d7108176691931b |
| 里程碑 M2 200 BEM（演示取消） | https://testnet.bscscan.com/tx/0xddd3a160ecc582f8fa5e25c4791d68695db875584c1409ab0a8c9edef400e2fb |
| 审批人 2、3 投票取消 M2 → 200 BEM 退回资金池 | https://testnet.bscscan.com/tx/0x8192dcb968651386891c8b8058d137d46975d48d1c66c1f5e7f68e208d32b660 · https://testnet.bscscan.com/tx/0x402851f6652c335594050b786b15ac194f3cf9abbb3a81b61452ea681fbcd5f5 |
| 里程碑 M3 100 BEM（保持开放，供演示申请） | https://testnet.bscscan.com/tx/0x4fb9144800a75eeceeb50f7defea10c106322c2f826d0ddb709590ad26a9fe97 |

结果核对：开发者收到 **297 BEM**，`0x…dEaD` 增加 **3 BEM**（正好 1%）；合约余额 700 BEM = 未分配 600 + M3 已分配 100；`totalPaid=297`，`totalBurned=3`。

## 六、前端

- `frontend/` 纯静态页面，ethers v6 本地加载（`ethers.umd.min.js`，不依赖 CDN），可以直接放进 TapeOut 容器或 GitHub Pages。
- 中文优先，右上角 **中 / EN** 切换（记住选择）；手机优先布局；顶部红色横幅「测试网演示」。
- 页面：资助池列表（托管中 / 已发放 / 已销毁）、资助池详情（里程碑、申请、票数、链上记录，全部链接到 BscScan，原始网址直接显示）、创建资助池、申请、审批人面板（选定 / 放款 / 取消）、资助方面板（新建里程碑、7 天公示取回）、受助人操作、我的面板。
- 钱包：注入式钱包（TokenPocket / MetaMask 内置浏览器），自动切换 / 添加网络。测试网页面有“领取 1000 测试 BEM”按钮。
- 网络配置在 `frontend/config.js`：`active: "bscTestnet"` 改为 `"bsc"` 并填入主网合约地址即可切到主网。

## 七、上主网需要做的

1. **轻量审计**：至少找 1~2 位熟悉 Solidity 的人做 audit-lite 复核（合约约 400 行，没有外部依赖，只用 OpenZeppelin），再跑一遍 Slither。重点看：多签计票、时间锁、放款/取消的资金记账。
2. **确认真实 BEM 是标准 ERC20**（不扣转账手续费、没有黑名单 / 暂停之类会卡住放款的逻辑）。
3. **审批人用多签钱包**：推荐 **Safe（https://app.safe.global ，支持 BNB Chain）**。每个审批人地址最好本身就是一个 Safe 或硬件钱包；基金会做资助方时，资助方地址也建议用 Safe。
4. **主网部署**：用一个只放少量 BNB 的新钱包部署（构造参数只有 BEM 地址），在 BscScan 上验证并开源源码。部署后合约没有任何管理权限，部署钱包之后用不到。
5. 改 `frontend/config.js` 切到主网，去掉测试网横幅；先用小额（比如 50 BEM）建一个真实资助池走一遍，再请基金方存入大额。

## 八、可以直接发的推文

```
社区基金现在靠推文认捐、私信发钱，没法公开查。

我做了个 TapeOut 生态资助托管板：BEM 先锁进合约，3 个审批人里 2 个同意才放款，放款销毁 1%，每一笔都能在 BscScan 查。

测试网演示，欢迎试用提意见：
https://renyuefeng1-dot.github.io/bem-grants/
```
（加权字数 218 / 280）
