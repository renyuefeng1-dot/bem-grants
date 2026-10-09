// 网络配置：现在指向 BSC 测试网（测试网演示）。上主网时把 active 改成 "bsc" 并填入主网合约地址。
window.GRANTS_CONFIG = {
  active: "bscTestnet",
  networks: {
    bscTestnet: {
      testnet: true,
      chainId: 97,
      chainName: "BNB Smart Chain Testnet",
      rpcUrl: "https://bsc-testnet-rpc.publicnode.com",
      explorer: "https://testnet.bscscan.com",
      escrow: "0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF",
      token: "0xAf81078FA7DF6aF5E5bD97B98a358939600EC320", // 测试网 MockBEM（8 位小数，任何人可 mint）
      deployBlock: 135795605,
      faucet: "https://www.bnbchain.org/en/testnet-faucet",
      // 演示数据的显示名：测试网上早先写入链上的标题用的是旧叫法，这里只改页面显示，不改链上数据
      labelOverrides: {
        pool: { 1: { zh: "演示任务池（测试网）", en: "Demo task pool (testnet)", zhDesc: "1000 BEM，3 个验收人里 2 人同意即结算，结算销毁 1%", enDesc: "1000 BEM, 2-of-3 reviewer sign-off to settle, 1% burned on settlement" } },
        task: { 2: { zh: "演示：将被取消的任务", en: "Demo: task to be cancelled" },
                3: { zh: "TapeNow 排错手册英文版", en: "English version of the TapeNow troubleshooting guide", zhDesc: "开放接单中", enDesc: "Open to offers" } }
      }
    },
    bsc: {
      testnet: false,
      chainId: 56,
      chainName: "BNB Smart Chain",
      rpcUrl: "https://bsc-dataseed.bnbchain.org",
      explorer: "https://bscscan.com",
      escrow: "", // 审计后部署再填
      token: "0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a", // 真实 BEM
      deployBlock: 0
    }
  },
  logChunk: 49000 // 公共 RPC 单次 getLogs 最大区块范围
};
