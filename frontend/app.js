/* TapeOut 生态资助托管板 —— 纯静态前端（无 CDN，ethers 本地加载），可放入 TapeOut 容器 / GitHub Pages */
(() => {
const E = window.ethers, CFG = window.GRANTS_CONFIG;
const NET = CFG.networks[new URLSearchParams(location.search).get("net") || CFG.active] || CFG.networks[CFG.active];
const DEAD = "0x000000000000000000000000000000000000dEaD";

// ------------------------------------------------------------------ i18n
const I18N = {
zh: {
  appName:"TapeOut 生态资助托管板", connect:"连接钱包", connected:"已连接", navPools:"资助池", navCreate:"创建资助池", navMe:"我的面板", navAbout:"规则说明",
  bannerTest:"测试网演示 · BSC Testnet · 代币是测试 BEM，没有任何价值", bannerMain:"BSC 主网 · 真实 BEM",
  totalLocked:"托管中", totalPaid:"已发放", totalBurned:"已销毁", pools:"资助池列表", noPools:"还没有资助池", loading:"加载中…",
  pool:"资助池", funder:"资助方", approvers:"审批人", threshold:"放款需要", sig:"签名", burn:"放款销毁", available:"未分配", allocated:"已分配",
  deposited:"累计存入", withdrawn:"资助方已取回", milestones:"里程碑 / 资助项目", noMs:"还没有里程碑", amount:"金额", deadline:"申请截止", recipient:"受助人",
  status:"状态", Open:"开放申请", Awarded:"已选定", Paid:"已放款", Cancelled:"已取消", apps:"申请", noApps:"暂无申请", delivery:"交付链接",
  releaseVotes:"放款票", cancelVotes:"取消票", awardVotes:"票", applyHere:"申请这个项目", applyPh:"你的方案 / 作品链接（GitHub、推文、IPFS…）", applyBtn:"提交申请",
  topUp:"追加资金（任何人）", topUpBtn:"授权并追加", approverPanel:"审批人面板", funderPanel:"资助方面板", recipientPanel:"受助人操作",
  voteAward:"投票选定", voteRelease:"同意放款", voteCancel:"投票取消（退回资金池）", youVoted:"你已投", submitDelivery:"提交交付", deliveryPh:"交付链接",
  relinquish:"放弃（退回资金池）", expire:"标记过期（退回资金池）", newMs:"新建里程碑", msTitle:"标题", msDesc:"说明 / 链接", days:"申请期（天）",
  directRecipient:"直接指定受助人（可留空，开放申请）", createMs:"创建里程碑", reqWithdraw:"申请取回未分配资金（7 天公示）", reqBtn:"发起取回申请",
  pendingWithdraw:"待执行取回", unlockAt:"可执行时间", execWithdraw:"执行取回", cancelWithdraw:"撤销取回申请", history:"链上记录",
  loadMore:"加载更早的记录", createPool:"创建资助池", poolTitle:"资助池名称", poolDesc:"说明（规则、方向、联系方式，可填链接）", depositAmt:"存入 BEM 数量",
  approversList:"审批人地址（每行一个，建议 3 个）", thresholdM:"放款需要几个审批人同意（M）", burnPct:"放款销毁比例 %（默认 1，最高 10）", createBtn:"授权并创建",
  myBal:"我的 BEM", needConnect:"请先连接钱包", noWallet:"没有检测到钱包。请在 TokenPocket / MetaMask 的内置浏览器里打开本页。", wrongNet:"请切换到",
  sent:"交易已发送，等待确认…", done:"交易成功", failed:"失败", approving:"正在授权 BEM…", fill:"请填写完整", contract:"合约", token:"代币", rpc:"RPC",
  explorer:"区块浏览器", myPools:"我是资助方的资助池", myApprover:"我是审批人的资助池", myRecipient:"我是受助人的项目", none:"无", go:"打开",
  todo:"待你处理", viewOnScan:"在 BscScan 查看", faucet:"测试网 BNB 水龙头", mintTest:"领取 1000 测试 BEM", only:"仅", tx:"交易",
  aboutHtml:`<h2>它是怎么运作的</h2>
<ol><li><b>资助方</b>（基金会、项目方、个人）创建资助池，把 BEM 锁进合约，并指定 N 个审批人和放款门槛 M（例如 2-of-3）。任何人都可以往池子里追加 BEM。</li>
<li>资助方或审批人从池子里划出<b>里程碑</b>（金额 + 申请截止时间）。这部分资金立即变为“已分配”。</li>
<li><b>开发者</b>提交申请（方案链接上链）。M 个审批人投票选定后，受助人确定。</li>
<li>受助人交付后提交链接，<b>M 个审批人同意放款</b>，合约立即把 BEM 打给受助人，并按池子设定比例（默认 1%）转入 0x…dEaD 销毁。</li></ol>
<h2>信任模型</h2>
<ul><li>审批人<b>能</b>：选定受助人、同意放款、取消未放款的里程碑（都需要 M 票）。</li>
<li>审批人<b>不能</b>：把钱转给自己或任何非受助人地址；单个审批人什么都做不了。</li>
<li>资助方<b>能</b>：取回“未分配”的余额，但必须提前 7 天在链上公示。</li>
<li>资助方<b>不能</b>：动已分配给里程碑的资金——这部分只能放给受助人，或经 M 票取消后退回资金池。</li>
<li>合约<b>没有 owner、不可升级</b>，没有任何管理员提款函数。每一步都有事件，可在 BscScan 公开查询。</li>
<li>无人获选的里程碑过了申请截止时间，任何人都可以标记过期，资金退回资金池；受助人也可以自愿放弃。</li></ul>`
},
en: {
  appName:"TapeOut Grant Escrow Board", connect:"Connect wallet", connected:"Connected", navPools:"Pools", navCreate:"Create pool", navMe:"My panel", navAbout:"How it works",
  bannerTest:"TESTNET DEMO · BSC Testnet · test BEM has no value", bannerMain:"BSC Mainnet · real BEM",
  totalLocked:"Locked", totalPaid:"Paid out", totalBurned:"Burned", pools:"Grant pools", noPools:"No pools yet", loading:"Loading…",
  pool:"Pool", funder:"Funder", approvers:"Approvers", threshold:"Release needs", sig:"sigs", burn:"Burn on payout", available:"Unallocated", allocated:"Allocated",
  deposited:"Deposited", withdrawn:"Withdrawn by funder", milestones:"Milestones / grants", noMs:"No milestones yet", amount:"Amount", deadline:"Apply by", recipient:"Recipient",
  status:"Status", Open:"Open", Awarded:"Awarded", Paid:"Paid", Cancelled:"Cancelled", apps:"Applications", noApps:"No applications", delivery:"Delivery",
  releaseVotes:"Release votes", cancelVotes:"Cancel votes", awardVotes:"votes", applyHere:"Apply for this grant", applyPh:"Your proposal / work link (GitHub, tweet, IPFS…)", applyBtn:"Apply",
  topUp:"Top up (anyone)", topUpBtn:"Approve & top up", approverPanel:"Approver panel", funderPanel:"Funder panel", recipientPanel:"Recipient actions",
  voteAward:"Vote to award", voteRelease:"Approve release", voteCancel:"Vote cancel (back to pool)", youVoted:"You voted", submitDelivery:"Submit delivery", deliveryPh:"Delivery link",
  relinquish:"Relinquish (back to pool)", expire:"Mark expired (back to pool)", newMs:"New milestone", msTitle:"Title", msDesc:"Description / link", days:"Application period (days)",
  directRecipient:"Direct recipient (optional; empty = open applications)", createMs:"Create milestone", reqWithdraw:"Withdraw unallocated funds (7-day notice)", reqBtn:"Request withdrawal",
  pendingWithdraw:"Pending withdrawal", unlockAt:"Executable at", execWithdraw:"Execute withdrawal", cancelWithdraw:"Cancel request", history:"On-chain history",
  loadMore:"Load older", createPool:"Create a grant pool", poolTitle:"Pool name", poolDesc:"Description (scope, rules, contact; links OK)", depositAmt:"BEM to deposit",
  approversList:"Approver addresses (one per line, 3 recommended)", thresholdM:"Approvals needed (M)", burnPct:"Burn % on payout (default 1, max 10)", createBtn:"Approve & create",
  myBal:"My BEM", needConnect:"Connect your wallet first", noWallet:"No wallet found. Open this page in TokenPocket / MetaMask's in-app browser.", wrongNet:"Please switch to",
  sent:"Transaction sent, waiting…", done:"Confirmed", failed:"Failed", approving:"Approving BEM…", fill:"Please fill all fields", contract:"Contract", token:"Token", rpc:"RPC",
  explorer:"Explorer", myPools:"Pools I fund", myApprover:"Pools I approve", myRecipient:"Grants I received", none:"None", go:"Open",
  todo:"needs you", viewOnScan:"View on BscScan", faucet:"Testnet BNB faucet", mintTest:"Mint 1000 test BEM", only:"only", tx:"tx",
  aboutHtml:`<h2>How it works</h2>
<ol><li>A <b>funder</b> creates a pool, locks BEM in the contract and names N approvers with an M-of-N release threshold (e.g. 2-of-3). Anyone can top up.</li>
<li>The funder or an approver carves out <b>milestones</b> (amount + application deadline). That amount becomes “allocated”.</li>
<li><b>Builders</b> apply (proposal link stored on-chain). When M approvers vote for one application, the recipient is set.</li>
<li>After delivery, <b>M approvers approve release</b>; the contract pays the recipient and sends the pool's burn share (default 1%) to 0x…dEaD.</li></ol>
<h2>Trust model</h2>
<ul><li>Approvers <b>can</b>: award, release, cancel unpaid milestones — each needs M votes.</li>
<li>Approvers <b>cannot</b>: send funds to themselves or anyone but the recipient; a single approver can do nothing alone.</li>
<li>The funder <b>can</b> withdraw unallocated balance only after a 7-day on-chain notice.</li>
<li>The funder <b>cannot</b> touch allocated funds — they only go to the recipient, or back to the pool by an M-of-N cancel.</li>
<li><b>No owner, not upgradeable</b>, no admin withdrawal. Every step emits an event visible on BscScan.</li>
<li>Unawarded milestones past their deadline can be expired by anyone (funds return to the pool); a recipient may also relinquish.</li></ul>`
}};
let lang = localStorage.getItem("grants_lang") === "en" ? "en" : "zh"; // 中文优先
const t = k => (I18N[lang] && I18N[lang][k]) ?? I18N.zh[k] ?? k;
function applyI18n(){ document.documentElement.lang = lang === "zh" ? "zh-CN" : "en"; document.title = t("appName");
  document.querySelectorAll("[data-i18n]").forEach(el => el.textContent = t(el.dataset.i18n));
  document.getElementById("banner").textContent = NET.testnet ? t("bannerTest") : t("bannerMain");
  document.getElementById("banner").style.background = NET.testnet ? "#d33" : "#1d6b3a";
  if (me) document.getElementById("connect").textContent = t("connected"); }

// ------------------------------------------------------------------ chain
const ABI = [
 "function token() view returns(address)","function poolCount() view returns(uint256)","function milestoneCount() view returns(uint256)",
 "function totalLocked() view returns(uint256)","function totalPaid() view returns(uint256)","function totalBurned() view returns(uint256)",
 "function WITHDRAW_DELAY() view returns(uint256)","function isApprover(uint256,address) view returns(bool)",
 "function getPool(uint256) view returns(tuple(address funder,uint16 burnBps,uint8 threshold,uint64 createdAt,uint64 withdrawUnlockAt,uint256 withdrawAmount,uint256 available,uint256 allocated,uint256 totalDeposited,uint256 totalPaid,uint256 totalBurned,uint256 totalWithdrawn,string uri) pool,address[] approvers)",
 "function getPoolMilestoneIds(uint256) view returns(uint256[])",
 "function getMilestone(uint256) view returns(tuple(uint256 poolId,uint256 amount,uint64 deadline,uint8 status,address recipient,uint8 releaseVotes,uint8 cancelVotes,string uri,string deliveryURI))",
 "function applicationCount(uint256) view returns(uint256)",
 "function getApplications(uint256,uint256,uint256) view returns(tuple(address applicant,uint64 appliedAt,uint8 awardVotes,string uri)[])",
 "function votesOf(uint256,address) view returns(uint256 awardAppPlus1,bool release,bool cancel)",
 "function createPool(uint256,string,address[],uint8,uint16) returns(uint256)","function topUp(uint256,uint256)",
 "function createMilestone(uint256,uint256,uint64,string,address) returns(uint256)","function applyFor(uint256,string) returns(uint256)",
 "function voteAward(uint256,uint256)","function submitDelivery(uint256,string)","function voteRelease(uint256)","function voteCancel(uint256)",
 "function expire(uint256)","function relinquish(uint256)","function requestWithdraw(uint256,uint256)","function cancelWithdraw(uint256)","function executeWithdraw(uint256)",
 "event PoolCreated(uint256 indexed poolId,address indexed funder,uint256 amount,uint8 threshold,uint16 burnBps,address[] approvers,string uri)",
 "event ToppedUp(uint256 indexed poolId,address indexed from,uint256 amount)",
 "event MilestoneCreated(uint256 indexed poolId,uint256 indexed milestoneId,address indexed creator,uint256 amount,uint64 deadline,address recipient,string uri)",
 "event Applied(uint256 indexed milestoneId,uint256 indexed appIndex,address indexed applicant,string uri)",
 "event AwardVoted(uint256 indexed milestoneId,uint256 indexed appIndex,address indexed approver,uint8 votes)",
 "event AwardVoteRevoked(uint256 indexed milestoneId,uint256 indexed appIndex,address indexed approver)",
 "event Awarded(uint256 indexed milestoneId,uint256 indexed appIndex,address indexed recipient)",
 "event DeliverySubmitted(uint256 indexed milestoneId,address indexed recipient,string uri)",
 "event ReleaseVoted(uint256 indexed milestoneId,address indexed approver,uint8 votes)",
 "event Released(uint256 indexed poolId,uint256 indexed milestoneId,address indexed recipient,uint256 amount,uint256 paid,uint256 burned)",
 "event Burned(uint256 indexed poolId,uint256 amount)",
 "event CancelVoted(uint256 indexed milestoneId,address indexed approver,uint8 votes)",
 "event MilestoneCancelled(uint256 indexed poolId,uint256 indexed milestoneId,uint256 amount)",
 "event MilestoneExpired(uint256 indexed poolId,uint256 indexed milestoneId,uint256 amount)",
 "event Relinquished(uint256 indexed poolId,uint256 indexed milestoneId,address indexed recipient,uint256 amount)",
 "event WithdrawRequested(uint256 indexed poolId,uint256 amount,uint64 unlockAt)",
 "event WithdrawRequestCancelled(uint256 indexed poolId)",
 "event Withdrawn(uint256 indexed poolId,address indexed funder,uint256 amount)",
 "error ZeroAmount()","error BadThreshold()","error BadApprover()","error BadBurnBps()","error FeeOnTransferNotSupported()","error NoPool()","error NoMilestone()",
 "error NotFunder()","error NotApprover()","error NotFunderOrApprover()","error NotRecipient()","error Insufficient()","error BadDeadline()","error BadStatus()",
 "error ApplicationsClosed()","error DeadlineNotPassed()","error BadApplication()","error AlreadyVoted()","error NoWithdrawRequest()","error TooEarly()"
];
const ERC20 = ["function decimals() view returns(uint8)","function balanceOf(address) view returns(uint256)","function allowance(address,address) view returns(uint256)","function approve(address,uint256) returns(bool)","function mint(address,uint256)"];
const IFACE = new E.Interface(ABI);
const ro = new E.JsonRpcProvider(NET.rpcUrl, NET.chainId, { staticNetwork: true, batchMaxCount: 20 });
let signer = null, me = null, dec = 8;
const esc = () => new E.Contract(NET.escrow, ABI, signer || ro);
const tok = () => new E.Contract(NET.token, ERC20, signer || ro);
const ST = ["None","Open","Awarded","Paid","Cancelled"];

// ------------------------------------------------------------------ helpers
const h = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const $ = id => document.getElementById(id);
const fmt = v => { let s = E.formatUnits(v, dec); if (s.includes(".")) s = s.replace(/0+$/, "").replace(/\.$/, "");
  const [i, d] = s.split("."); return i.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (d ? "." + d : ""); };
const short = a => a ? a.slice(0, 6) + "…" + a.slice(-4) : "";
const scanAddr = a => `${NET.explorer}/address/${a}`, scanTx = x => `${NET.explorer}/tx/${x}`;
const addrLink = a => `<a class="mono" href="${scanAddr(a)}" target="_blank" rel="noopener">${h(a)}</a>${me && a.toLowerCase() === me ? ' <span class="tag">me</span>' : ""}`;
const rawLink = u => `<a class="mono" href="${h(u)}" target="_blank" rel="noopener">${h(u)}</a>`;
const time = s => new Date(Number(s) * 1000).toLocaleString(lang === "zh" ? "zh-CN" : "en-US");
/** 显示用户写入的 URI：JSON{title,desc} / 链接（原样显示完整 URL） / 纯文本 */
function parseUri(u){ try { const j = JSON.parse(u); if (j && typeof j === "object") return { title: String(j.title || ""), desc: String(j.desc || "") }; } catch {} return { title: "", desc: String(u || "") }; }
function linkify(text){ return h(text).replace(/(https?:\/\/[^\s<]+|ipfs:\/\/[^\s<]+)/g, m => {
  const href = m.startsWith("ipfs://") ? "https://ipfs.io/ipfs/" + m.slice(7) : m; return `<a class="mono" href="${href}" target="_blank" rel="noopener">${m}</a>`; }); }
function toast(msg, ms = 4000){ const el = $("toast"); el.innerHTML = msg; el.style.display = "block"; clearTimeout(toast._t); if (ms) toast._t = setTimeout(() => el.style.display = "none", ms); }
function errMsg(e){
  const data = e?.data || e?.info?.error?.data || e?.error?.data || e?.revert?.data;
  if (typeof data === "string" && data.startsWith("0x")) { try { return IFACE.parseError(data).name; } catch {} }
  if (e?.revert?.name) return e.revert.name;
  return e?.shortMessage || e?.reason || e?.message || String(e);
}

// ------------------------------------------------------------------ wallet
async function connect(){
  if (!window.ethereum) return toast(t("noWallet"), 8000);
  const hex = "0x" + NET.chainId.toString(16);
  await window.ethereum.request({ method: "eth_requestAccounts" });
  try { await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hex }] }); }
  catch (e) { if (e.code === 4902 || e?.data?.originalError?.code === 4902) await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{ chainId: hex, chainName: NET.chainName, rpcUrls: [NET.rpcUrl], nativeCurrency: { name: "BNB", symbol: NET.testnet ? "tBNB" : "BNB", decimals: 18 }, blockExplorerUrls: [NET.explorer] }] }); else throw e; }
  const bp = new E.BrowserProvider(window.ethereum);
  const net = await bp.getNetwork();
  if (Number(net.chainId) !== NET.chainId) { toast(t("wrongNet") + " " + NET.chainName, 8000); return; }
  signer = await bp.getSigner(); me = (await signer.getAddress()).toLowerCase();
  const bal = await tok().balanceOf(me);
  $("acct").innerHTML = `${h(me)} · ${t("myBal")}: <b>${fmt(bal)}</b>`;
  applyI18n(); route();
}
if (window.ethereum?.on) { window.ethereum.on("accountsChanged", () => { signer = null; me = null; $("acct").textContent = ""; connect().catch(() => {}); });
  window.ethereum.on("chainChanged", () => location.reload()); }
async function send(fn){
  if (!signer) { toast(t("needConnect")); return false; }
  try { const tx = await fn(); toast(`${t("sent")}<br>${rawLink(scanTx(tx.hash))}`, 0); await tx.wait();
    toast(`✅ ${t("done")}<br>${rawLink(scanTx(tx.hash))}`, 8000); route(); connect().catch(() => {}); return true; }
  catch (e) { toast(`❌ ${t("failed")}: ${h(errMsg(e))}`, 8000); return false; }
}
async function ensureAllowance(amt){
  const a = await tok().allowance(me, NET.escrow);
  if (a >= amt) return true;
  toast(t("approving"), 0);
  try { await (await tok().approve(NET.escrow, amt)).wait(); return true; } catch (e) { toast(`❌ ${h(errMsg(e))}`, 8000); return false; }
}

// ------------------------------------------------------------------ pages
async function pageList(){
  const c = esc();
  const [n, L, P, B] = await Promise.all([c.poolCount(), c.totalLocked(), c.totalPaid(), c.totalBurned()]);
  let html = `<div class="stats"><div class="stat"><b>${fmt(L)}</b><small>${t("totalLocked")} BEM</small></div>
   <div class="stat"><b>${fmt(P)}</b><small>${t("totalPaid")} BEM</small></div><div class="stat burn"><b>🔥 ${fmt(B)}</b><small>${t("totalBurned")} BEM</small></div></div>
   <h2>${t("pools")}</h2>`;
  const ids = []; for (let i = Number(n); i >= 1 && ids.length < 50; i--) ids.push(i);
  const pools = await Promise.all(ids.map(i => c.getPool(i)));
  html += pools.map((r, k) => { const p = r.pool, u = parseUri(p.uri);
    return `<a href="#/pool/${ids[k]}" style="text-decoration:none;color:inherit"><div class="card"><b>#${ids[k]} ${h(u.title || u.desc.slice(0, 60))}</b>
     <div class="row muted" style="margin-top:6px"><div>${t("available")}: <b>${fmt(p.available)}</b></div><div>${t("allocated")}: <b>${fmt(p.allocated)}</b></div>
     <div>${t("totalPaid")}: <b>${fmt(p.totalPaid)}</b></div><div>🔥 ${fmt(p.totalBurned)}</div></div>
     <div class="muted">${t("threshold")} ${p.threshold}/${r.approvers.length} ${t("sig")} · ${t("burn")} ${Number(p.burnBps) / 100}% · ${t("funder")} ${short(p.funder)}</div></div></a>`; }).join("") || `<div class="card muted">${t("noPools")}</div>`;
  html += netInfo();
  return html;
}

function netInfo(){
  return `<div class="card muted"><div>${t("contract")}: ${rawLink(scanAddr(NET.escrow))}</div><div>${t("token")}: ${rawLink(scanAddr(NET.token))}</div>
   <div>${t("rpc")}: <span class="mono">${h(NET.rpcUrl)}</span> · chainId ${NET.chainId}</div><div>${t("explorer")}: ${rawLink(NET.explorer)}</div>
   ${NET.testnet ? `<div>${t("faucet")}: ${rawLink(NET.faucet)}</div><button class="ghost" onclick="G.mint()">${t("mintTest")}</button>` : ""}</div>`;
}

async function pagePool(id){
  const c = esc();
  const r = await c.getPool(id), p = r.pool, apprs = r.approvers.map(a => a.toLowerCase()), u = parseUri(p.uri);
  const isF = me && p.funder.toLowerCase() === me, isA = me && apprs.includes(me);
  const mids = (await c.getPoolMilestoneIds(id)).map(Number).reverse();
  const ms = await Promise.all(mids.map(m => c.getMilestone(m)));
  const appsArr = await Promise.all(mids.map(m => c.getApplications(m, 0, 100)));
  const votes = isA ? await Promise.all(mids.map(m => c.votesOf(m, me))) : [];
  const now = Date.now() / 1000;
  let html = `<div class="card"><h2>#${id} ${h(u.title)}</h2>${u.desc ? `<div>${linkify(u.desc)}</div>` : ""}
   <div class="stats" style="margin-top:10px"><div class="stat"><b>${fmt(p.available)}</b><small>${t("available")}</small></div>
   <div class="stat"><b>${fmt(p.allocated)}</b><small>${t("allocated")}</small></div><div class="stat"><b>${fmt(p.totalPaid)}</b><small>${t("totalPaid")}</small></div></div>
   <div class="muted" style="margin-top:8px">${t("deposited")} ${fmt(p.totalDeposited)} · 🔥 ${t("totalBurned")} ${fmt(p.totalBurned)} · ${t("withdrawn")} ${fmt(p.totalWithdrawn)}</div>
   <div class="muted">${t("burn")}: ${Number(p.burnBps) / 100}% → <span class="mono">${DEAD}</span></div>
   <div>${t("funder")}: ${addrLink(p.funder)}</div>
   <div>${t("approvers")} (${t("threshold")} <b>${p.threshold}/${apprs.length}</b>):</div>${r.approvers.map(a => `<div>· ${addrLink(a)}</div>`).join("")}
   ${p.withdrawUnlockAt > 0n ? `<div class="card" style="border-color:#c0392b">⚠️ ${t("pendingWithdraw")}: <b>${fmt(p.withdrawAmount)}</b> BEM · ${t("unlockAt")} ${time(p.withdrawUnlockAt)}</div>` : ""}
   <h3>${t("topUp")}</h3><div class="row"><input id="topAmt" inputmode="decimal" placeholder="BEM"><button onclick="G.topUp(${id})">${t("topUpBtn")}</button></div></div>`;

  if (isF || isA) {
    html += `<div class="card panel"><h3>${isF ? t("funderPanel") : ""}${isF && isA ? " / " : ""}${isA ? t("approverPanel") : ""}</h3>
     <h3>${t("newMs")}</h3><label>${t("msTitle")}</label><input id="msTitle"><label>${t("msDesc")}</label><textarea id="msDesc"></textarea>
     <div class="row"><div><label>${t("amount")} (BEM)</label><input id="msAmt" inputmode="decimal"></div><div><label>${t("days")}</label><input id="msDays" inputmode="numeric" value="14"></div></div>
     <label>${t("directRecipient")}</label><input id="msTo" class="mono" placeholder="0x…"><button onclick="G.createMs(${id})">${t("createMs")}</button>`;
    if (isF) html += `<h3>${t("reqWithdraw")}</h3><div class="row"><input id="wdAmt" inputmode="decimal" placeholder="≤ ${fmt(p.available)}"><button class="ghost" onclick="G.reqWd(${id})">${t("reqBtn")}</button></div>
      ${p.withdrawUnlockAt > 0n ? `<button ${now < Number(p.withdrawUnlockAt) ? "disabled" : ""} onclick="G.call('executeWithdraw',${id})">${t("execWithdraw")}</button><button class="ghost" onclick="G.call('cancelWithdraw',${id})">${t("cancelWithdraw")}</button>` : ""}`;
    html += `</div>`;
  }

  html += `<h2>${t("milestones")}</h2>`;
  html += ms.map((m, k) => { const mid = mids[k], st = ST[Number(m.status)], mu = parseUri(m.uri), apps = appsArr[k], v = votes[k];
    const isR = me && m.recipient.toLowerCase() === me, open = st === "Open", awarded = st === "Awarded";
    let s = `<div class="card" id="m${mid}"><div><span class="tag ${st}">${t(st)}</span> <b>M${mid} ${h(mu.title)}</b></div>${mu.desc ? `<div>${linkify(mu.desc)}</div>` : ""}
     <div class="row muted"><div>${t("amount")}: <b style="color:#f0b90b">${fmt(m.amount)}</b> BEM</div><div>${t("deadline")}: ${time(m.deadline)}</div></div>`;
    if (m.recipient !== E.ZeroAddress) s += `<div>${t("recipient")}: ${addrLink(m.recipient)}</div>`;
    if (m.deliveryURI) s += `<div>${t("delivery")}: ${linkify(m.deliveryURI)}</div>`;
    if (awarded || st === "Paid" || m.cancelVotes > 0) s += `<div class="muted">${t("releaseVotes")} ${m.releaseVotes}/${p.threshold} · ${t("cancelVotes")} ${m.cancelVotes}/${p.threshold}</div>`;
    s += `<div class="muted" style="margin-top:6px">${t("apps")} (${apps.length})</div>`;
    s += apps.map((a, i) => `<div class="app"><div>#${i} ${addrLink(a.applicant)} <span class="muted">${time(a.appliedAt)} · ${a.awardVotes} ${t("awardVotes")}</span></div><div>${linkify(a.uri)}</div>
      ${isA && open ? (v && Number(v.awardAppPlus1) === i + 1 ? `<span class="tag">✔ ${t("youVoted")}</span>` : `<button onclick="G.call('voteAward',${mid},${i})">${t("voteAward")}</button>`) : ""}</div>`).join("") || `<div class="muted">${t("noApps")}</div>`;
    if (open && now <= Number(m.deadline)) s += `<div class="app"><b>${t("applyHere")}</b><textarea id="ap${mid}" placeholder="${t("applyPh")}"></textarea><button onclick="G.apply(${mid})">${t("applyBtn")}</button></div>`;
    if (open && now > Number(m.deadline)) s += `<button class="ghost" onclick="G.call('expire',${mid})">${t("expire")}</button>`;
    if (isR && awarded) s += `<div class="panel"><b>${t("recipientPanel")}</b><input id="dl${mid}" placeholder="${t("deliveryPh")}"><button onclick="G.deliver(${mid})">${t("submitDelivery")}</button><button class="ghost" onclick="G.call('relinquish',${mid})">${t("relinquish")}</button></div>`;
    if (isA && (open || awarded)) { s += `<div class="panel" style="margin-top:8px"><b>${t("approverPanel")}</b><br>`;
      if (awarded) s += v.release ? `<span class="tag">✔ ${t("youVoted")}: ${t("voteRelease")}</span>` : `<button onclick="G.call('voteRelease',${mid})">${t("voteRelease")} (${fmt(m.amount * BigInt(10000 - Number(p.burnBps)) / 10000n)} → ${short(m.recipient)}, 🔥${fmt(m.amount * BigInt(p.burnBps) / 10000n)})</button>`;
      s += v.cancel ? ` <span class="tag">✔ ${t("youVoted")}: ${t("voteCancel")}</span>` : ` <button class="red" onclick="G.call('voteCancel',${mid})">${t("voteCancel")}</button>`;
      s += `</div>`; }
    return s + `</div>`; }).join("") || `<div class="card muted">${t("noMs")}</div>`;

  html += `<h2>${t("history")}</h2><div class="card" id="hist">${t("loading")}</div>`;
  setTimeout(() => loadHistory(id, new Set(mids.map(String)), true), 0);
  return html;
}

// 链上记录：从最新区块往回按 49000 区块分段扫描（公共 RPC 限制），只保留与本资助池相关的事件
let histState = null;
const EVZH = { PoolCreated:"创建资助池", ToppedUp:"追加资金", MilestoneCreated:"新建里程碑", Applied:"提交申请", AwardVoted:"投票选定", AwardVoteRevoked:"撤回选定票",
  Awarded:"选定受助人", DeliverySubmitted:"提交交付", ReleaseVoted:"同意放款", Released:"已放款", Burned:"销毁", CancelVoted:"投票取消", MilestoneCancelled:"里程碑已取消",
  MilestoneExpired:"里程碑过期", Relinquished:"受助人放弃", WithdrawRequested:"申请取回（7 天公示）", WithdrawRequestCancelled:"撤销取回", Withdrawn:"资助方取回" };
const argsOf = ev => Object.fromEntries(ev.fragment.inputs.map((inp, i) => [inp.name, ev.args[i]]));
async function loadHistory(poolId, midSet, reset){
  if (reset) histState = { poolId, midSet, to: await ro.getBlockNumber(), items: [] };
  const S = histState; if (S.poolId !== poolId) return;
  const chunks = 8; let scanned = 0;
  while (S.to >= NET.deployBlock && scanned < chunks) {
    const from = Math.max(NET.deployBlock, S.to - CFG.logChunk + 1);
    try { const logs = await ro.getLogs({ address: NET.escrow, fromBlock: from, toBlock: S.to });
      for (const l of logs.reverse()) { let ev; try { ev = IFACE.parseLog(l); } catch { continue; }
        const a = argsOf(ev), pid = a.poolId != null ? String(a.poolId) : null, mid = a.milestoneId != null ? String(a.milestoneId) : null;
        if (pid === String(poolId) || (mid && S.midSet.has(mid))) S.items.push({ ev, l }); } }
    catch (e) { S.err = errMsg(e); break; }
    S.to = from - 1; scanned++;
  }
  const el = $("hist"); if (!el) return;
  el.innerHTML = S.items.map(({ ev, l }) => { const a = argsOf(ev); const bits = [];
      if ("milestoneId" in a) bits.push("M" + a.milestoneId);
      if ("amount" in a) bits.push(fmt(a.amount) + " BEM");
      if ("paid" in a) bits.push("→ " + short(a.recipient) + " " + fmt(a.paid) + ", 🔥 " + fmt(a.burned));
      for (const k of ["approver", "applicant", "from", "funder"]) if (k in a && ev.name !== "PoolCreated") bits.push(short(a[k]));
      if ("votes" in a) bits.push(a.votes + " " + t("awardVotes"));
      return `<div class="hist"><b>${lang === "zh" ? (EVZH[ev.name] || ev.name) : ev.name}</b> ${h(bits.join(" · "))}<br><span class="muted">#${l.blockNumber}</span> ${rawLink(scanTx(l.transactionHash))}</div>`; }).join("")
    + (S.err ? `<div class="muted">${h(S.err)}</div>` : "")
    + (S.to >= NET.deployBlock ? `<button class="ghost" onclick="G.more()">${t("loadMore")}</button>` : (S.items.length ? "" : `<div class="muted">${t("none")}</div>`));
}

function pageCreate(){
  return `<div class="card"><h2>${t("createPool")}</h2>
   <label>${t("poolTitle")}</label><input id="cpTitle"><label>${t("poolDesc")}</label><textarea id="cpDesc"></textarea>
   <label>${t("depositAmt")}</label><input id="cpAmt" inputmode="decimal" placeholder="1000">
   <label>${t("approversList")}</label><textarea id="cpAppr" class="mono" placeholder="0x…&#10;0x…&#10;0x…"></textarea>
   <div class="row"><div><label>${t("thresholdM")}</label><input id="cpM" inputmode="numeric" value="2"></div><div><label>${t("burnPct")}</label><input id="cpBurn" inputmode="decimal" value="1"></div></div>
   <button onclick="G.createPool()">${t("createBtn")}</button></div>` + netInfo();
}

async function pageMe(){
  if (!me) return `<div class="card">${t("needConnect")}<br><button onclick="G.connect()">${t("connect")}</button></div>`;
  const c = esc(), n = Number(await c.poolCount()), mc = Number(await c.milestoneCount());
  const pools = await Promise.all(Array.from({ length: n }, (_, i) => c.getPool(i + 1)));
  const fund = [], appr = [];
  pools.forEach((r, i) => { if (r.pool.funder.toLowerCase() === me) fund.push(i + 1); if (r.approvers.some(a => a.toLowerCase() === me)) appr.push(i + 1); });
  const lim = Math.min(mc, 300), msAll = await Promise.all(Array.from({ length: lim }, (_, i) => c.getMilestone(mc - i)));
  const mine = msAll.map((m, i) => ({ m, id: mc - i })).filter(x => x.m.recipient.toLowerCase() === me);
  const plink = id => { const u = parseUri(pools[id - 1].pool.uri); return `<div><a href="#/pool/${id}">#${id} ${h(u.title || u.desc.slice(0, 50))}</a></div>`; };
  return `<div class="card"><h3>${t("myPools")}</h3>${fund.map(plink).join("") || t("none")}</div>
   <div class="card"><h3>${t("myApprover")}</h3>${appr.map(plink).join("") || t("none")}</div>
   <div class="card"><h3>${t("myRecipient")}</h3>${mine.map(x => `<div><a href="#/pool/${x.m.poolId}">M${x.id}</a> <span class="tag ${ST[Number(x.m.status)]}">${t(ST[Number(x.m.status)])}</span> ${fmt(x.m.amount)} BEM</div>`).join("") || t("none")}</div>`;
}

// ------------------------------------------------------------------ actions
const G = window.G = {
  connect: () => connect().catch(e => toast(h(errMsg(e)), 8000)),
  more: () => histState && loadHistory(histState.poolId, histState.midSet, false),
  call: (m, ...a) => send(() => esc()[m](...a)),
  async mint(){ if (!signer) return toast(t("needConnect")); send(() => tok().mint(me, E.parseUnits("1000", dec))); },
  async topUp(id){ if (!signer) return toast(t("needConnect")); const v = $("topAmt").value.trim(); if (!v) return toast(t("fill"));
    const amt = E.parseUnits(v, dec); if (await ensureAllowance(amt)) send(() => esc().topUp(id, amt)); },
  async createMs(id){ if (!signer) return toast(t("needConnect"));
    const title = $("msTitle").value.trim(), desc = $("msDesc").value.trim(), v = $("msAmt").value.trim(), d = Number($("msDays").value), to = $("msTo").value.trim();
    if (!title || !v || !(d > 0)) return toast(t("fill")); if (to && !E.isAddress(to)) return toast("address?");
    send(() => esc().createMilestone(id, E.parseUnits(v, dec), BigInt(Math.floor(Date.now() / 1000 + d * 86400)), JSON.stringify({ title, desc }), to || E.ZeroAddress)); },
  async reqWd(id){ const v = $("wdAmt").value.trim(); if (!v) return toast(t("fill")); send(() => esc().requestWithdraw(id, E.parseUnits(v, dec))); },
  async apply(mid){ const v = $("ap" + mid).value.trim(); if (!v) return toast(t("fill")); send(() => esc().applyFor(mid, v)); },
  async deliver(mid){ const v = $("dl" + mid).value.trim(); if (!v) return toast(t("fill")); send(() => esc().submitDelivery(mid, v)); },
  async createPool(){ if (!signer) return toast(t("needConnect"));
    const title = $("cpTitle").value.trim(), desc = $("cpDesc").value.trim(), v = $("cpAmt").value.trim(), M = Number($("cpM").value), burn = Number($("cpBurn").value);
    const appr = $("cpAppr").value.split(/[\s,;]+/).filter(Boolean);
    if (!title || !v || !appr.length || !(M >= 1)) return toast(t("fill"));
    if (appr.some(a => !E.isAddress(a))) return toast("approver address?");
    if (M > appr.length) return toast("M > N"); if (!(burn >= 0 && burn <= 10)) return toast("0–10%");
    const amt = E.parseUnits(v, dec);
    if (await ensureAllowance(amt)) { const ok = await send(() => esc().createPool(amt, JSON.stringify({ title, desc }), appr.map(a => E.getAddress(a)), M, Math.round(burn * 100)));
      if (ok) location.hash = "#/"; } }
};

// ------------------------------------------------------------------ router
async function route(){
  const parts = location.hash.replace(/^#\/?/, "").split("/"), r = parts[0] || "";
  document.querySelectorAll("nav a").forEach(a => a.classList.toggle("on", a.dataset.r === r || (r === "pool" && a.dataset.r === "")));
  const main = $("main");
  if (!NET.escrow) { main.innerHTML = `<div class="card">${t("contract")}: — (config.js)</div>`; return; }
  if (!route._busy) main.innerHTML = `<div class="card muted">${t("loading")}</div>`;
  try {
    let html;
    if (r === "pool") html = await pagePool(Number(parts[1]));
    else if (r === "create") html = pageCreate();
    else if (r === "me") html = await pageMe();
    else if (r === "about") html = `<div class="card">${t("aboutHtml")}</div>` + netInfo();
    else html = await pageList();
    main.innerHTML = html;
  } catch (e) { main.innerHTML = `<div class="card">❌ ${h(errMsg(e))}</div>` + netInfo(); }
}
$("connect").onclick = G.connect;
$("lang").onclick = () => { lang = lang === "zh" ? "en" : "zh"; localStorage.setItem("grants_lang", lang); applyI18n(); route(); };
window.addEventListener("hashchange", route);
applyI18n();
(async () => { try { dec = Number(await tok().decimals()); } catch {} route();
  if (window.ethereum) { try { const acc = await window.ethereum.request({ method: "eth_accounts" }); if (acc && acc.length) connect().catch(() => {}); } catch {} } })();
})();
