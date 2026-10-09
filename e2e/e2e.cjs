// 本地端到端检查：无钱包浏览 + 注入测试钱包（审批人 A1）投票。私钥只在本进程内使用，不输出。
const { chromium } = require('/workspace/anmao_server/node_modules/playwright-core');
const { ethers } = require('/workspace/anmao_server/node_modules/ethers');
const fs = require('fs');
const RPC = 'https://bsc-testnet-rpc.publicnode.com';
const keys = JSON.parse(fs.readFileSync(__dirname + '/../.testkeys.json')).data;
const URL = process.env.URL || 'http://127.0.0.1:8765/frontend/';
(async () => {
  const provider = new ethers.JsonRpcProvider(RPC, 97);
  const w = new ethers.Wallet(keys[0].private_key, provider);
  const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE', m.text()); });
  // 1) 无钱包浏览
  await page.goto(URL + '#/', { waitUntil: 'networkidle' });
  await page.waitForSelector('.stats', { timeout: 30000 });
  await page.screenshot({ path: 'e2e/01_list_zh.png', fullPage: true });
  await page.goto(URL + '#/pool/1'); await page.waitForSelector('#m1', { timeout: 30000 });
  await page.waitForFunction(() => !document.getElementById('hist').textContent.includes('加载中'), null, { timeout: 60000 });
  await page.screenshot({ path: 'e2e/02_pool_zh.png', fullPage: true });
  console.log('hist entries', await page.$$eval('.hist', e => e.length));
  await page.click('#lang'); await page.waitForTimeout(3000);
  await page.screenshot({ path: 'e2e/03_pool_en.png', fullPage: true });
  await page.click('#lang');
  // 2) 注入钱包
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  await ctx2.exposeBinding('__rpc', async (_s, method, params) => {
    if (method === 'eth_requestAccounts' || method === 'eth_accounts') return [w.address];
    if (method === 'eth_chainId') return '0x61';
    if (method === 'wallet_switchEthereumChain' || method === 'wallet_addEthereumChain') return null;
    if (method === 'eth_sendTransaction') { const tx = params[0];
      const r = await w.sendTransaction({ to: tx.to, data: tx.data, value: tx.value || 0, gasPrice: 1000000000n, type: 0 }); console.log('TX', method, r.hash); return r.hash; }
    return provider.send(method, params || []);
  });
  await ctx2.addInitScript(() => { window.ethereum = { isMetaMask: true, on(){}, request: ({ method, params }) => window.__rpc(method, params) }; });
  const p2 = await ctx2.newPage();
  p2.on('pageerror', e => console.log('PAGEERROR2', e.message));
  await p2.goto(URL + '#/pool/1'); await p2.waitForSelector('#m3 .panel', { timeout: 60000 });
  await p2.screenshot({ path: 'e2e/04_approver_zh.png', fullPage: true });
  const btn = p2.locator('#m3 button', { hasText: '投票选定' });
  console.log('award buttons on M3:', await btn.count());
  if (await btn.count()) { await btn.first().click(); await p2.waitForSelector('#toast:has-text("交易成功")', { timeout: 90000 }); console.log('toast:', await p2.textContent('#toast')); }
  await p2.waitForTimeout(4000);
  await p2.screenshot({ path: 'e2e/05_after_vote.png', fullPage: true });
  console.log('M3 text:', (await p2.textContent('#m3')).replace(/\s+/g, ' ').slice(0, 300));
  await p2.goto(URL + '#/me'); await p2.waitForTimeout(5000);
  console.log('me:', (await p2.textContent('main')).replace(/\s+/g, ' ').slice(0, 200));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
