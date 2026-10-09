// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GrantEscrow —— TapeOut 生态资助托管板
/// @notice 资助方把 BEM 锁进资助池，由 M-of-N 审批人决定把里程碑奖励发给谁、何时放款。
///         - 无 owner、不可升级、没有任何管理员提取资金的函数；
///         - 已分配给里程碑的资金只能：多签放款给受助人 / 多签取消退回资金池 / 受助人自愿放弃退回资金池；
///         - 资助方只能取回“未分配”的余额，且须提前 7 天公示（WITHDRAW_DELAY）；
///         - 放款时按资金池设定的比例（0~10%）转入 0x...dEaD 销毁；
///         - 拒绝转账收费（fee-on-transfer）代币：到账金额必须等于转账金额。
contract GrantEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------ 常量
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint16 public constant MAX_BURN_BPS = 1000; // 10%
    uint16 public constant DEFAULT_BURN_BPS = 100; // 1%（前端默认值）
    uint256 public constant WITHDRAW_DELAY = 7 days;
    uint256 public constant MAX_APPROVERS = 20;
    uint256 public constant MIN_DEADLINE_DELAY = 1 hours;

    IERC20 public immutable token;

    // ------------------------------------------------------------------ 数据结构
    enum MStatus {
        None,
        Open, // 开放申请，尚未确定受助人
        Awarded, // 已选定受助人，等待交付和放款
        Paid, // 已放款
        Cancelled // 已取消 / 过期 / 放弃，资金已退回资金池
    }

    struct Pool {
        address funder;
        uint16 burnBps;
        uint8 threshold; // M
        uint64 createdAt;
        uint64 withdrawUnlockAt; // 0 = 没有待执行的取回申请
        uint256 withdrawAmount; // 申请取回的金额
        uint256 available; // 未分配余额
        uint256 allocated; // 已分配给未完成里程碑的金额
        uint256 totalDeposited;
        uint256 totalPaid; // 受助人实际收到
        uint256 totalBurned;
        uint256 totalWithdrawn;
        string uri; // 标题/说明（IPFS 或 URL 或 JSON 文本）
    }

    struct Milestone {
        uint256 poolId;
        uint256 amount;
        uint64 deadline; // 申请截止时间（之后无人获选可被任何人标记过期）
        MStatus status;
        address recipient;
        uint8 releaseVotes;
        uint8 cancelVotes;
        string uri; // 任务说明
        string deliveryURI; // 受助人提交的交付链接
    }

    struct Application {
        address applicant;
        uint64 appliedAt;
        uint8 awardVotes;
        string uri;
    }

    uint256 public poolCount;
    uint256 public milestoneCount;

    mapping(uint256 => Pool) internal _pools;
    mapping(uint256 => address[]) internal _approvers;
    mapping(uint256 => mapping(address => bool)) public isApprover;
    mapping(uint256 => uint256[]) internal _poolMilestones;

    mapping(uint256 => Milestone) internal _milestones;
    mapping(uint256 => Application[]) internal _applications;

    // milestoneId => approver => 所投申请编号 + 1（0 = 未投）
    mapping(uint256 => mapping(address => uint256)) public awardVoteOf;
    mapping(uint256 => mapping(address => bool)) public releaseVoted;
    mapping(uint256 => mapping(address => bool)) public cancelVoted;

    // 全局统计
    uint256 public totalLocked; // 当前合约内托管总额
    uint256 public totalPaid;
    uint256 public totalBurned;

    // ------------------------------------------------------------------ 事件
    event PoolCreated(
        uint256 indexed poolId, address indexed funder, uint256 amount, uint8 threshold, uint16 burnBps, address[] approvers, string uri
    );
    event ToppedUp(uint256 indexed poolId, address indexed from, uint256 amount);
    event MilestoneCreated(
        uint256 indexed poolId, uint256 indexed milestoneId, address indexed creator, uint256 amount, uint64 deadline, address recipient, string uri
    );
    event Applied(uint256 indexed milestoneId, uint256 indexed appIndex, address indexed applicant, string uri);
    event AwardVoted(uint256 indexed milestoneId, uint256 indexed appIndex, address indexed approver, uint8 votes);
    event AwardVoteRevoked(uint256 indexed milestoneId, uint256 indexed appIndex, address indexed approver);
    event Awarded(uint256 indexed milestoneId, uint256 indexed appIndex, address indexed recipient);
    event DeliverySubmitted(uint256 indexed milestoneId, address indexed recipient, string uri);
    event ReleaseVoted(uint256 indexed milestoneId, address indexed approver, uint8 votes);
    event Released(uint256 indexed poolId, uint256 indexed milestoneId, address indexed recipient, uint256 amount, uint256 paid, uint256 burned);
    event Burned(uint256 indexed poolId, uint256 amount);
    event CancelVoted(uint256 indexed milestoneId, address indexed approver, uint8 votes);
    event MilestoneCancelled(uint256 indexed poolId, uint256 indexed milestoneId, uint256 amount);
    event MilestoneExpired(uint256 indexed poolId, uint256 indexed milestoneId, uint256 amount);
    event Relinquished(uint256 indexed poolId, uint256 indexed milestoneId, address indexed recipient, uint256 amount);
    event WithdrawRequested(uint256 indexed poolId, uint256 amount, uint64 unlockAt);
    event WithdrawRequestCancelled(uint256 indexed poolId);
    event Withdrawn(uint256 indexed poolId, address indexed funder, uint256 amount);

    // ------------------------------------------------------------------ 错误
    error ZeroAmount();
    error BadThreshold();
    error BadApprover();
    error BadBurnBps();
    error FeeOnTransferNotSupported();
    error NoPool();
    error NoMilestone();
    error NotFunder();
    error NotApprover();
    error NotFunderOrApprover();
    error NotRecipient();
    error Insufficient();
    error BadDeadline();
    error BadStatus();
    error ApplicationsClosed();
    error DeadlineNotPassed();
    error BadApplication();
    error AlreadyVoted();
    error NoWithdrawRequest();
    error TooEarly();

    constructor(IERC20 _token) {
        require(address(_token) != address(0), "token=0");
        token = _token;
    }

    // ------------------------------------------------------------------ 修饰
    modifier poolExists(uint256 poolId) {
        if (poolId == 0 || poolId > poolCount) revert NoPool();
        _;
    }

    modifier onlyApprover(uint256 poolId) {
        if (!isApprover[poolId][msg.sender]) revert NotApprover();
        _;
    }

    function _ms(uint256 id) internal view returns (Milestone storage m) {
        if (id == 0 || id > milestoneCount) revert NoMilestone();
        m = _milestones[id];
    }

    /// 拉取代币并要求到账 == amount（拒绝转账收费代币）
    function _pull(address from, uint256 amount) internal {
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        if (token.balanceOf(address(this)) - before != amount) revert FeeOnTransferNotSupported();
    }

    // ------------------------------------------------------------------ 资助池
    /// @notice 创建资助池并存入 BEM（需先 approve）。
    /// @param burnBps 放款销毁比例（基点，0~1000；推荐 DEFAULT_BURN_BPS=100 即 1%）
    function createPool(uint256 amount, string calldata uri, address[] calldata approvers, uint8 threshold, uint16 burnBps)
        external
        nonReentrant
        returns (uint256 poolId)
    {
        if (amount == 0) revert ZeroAmount();
        uint256 n = approvers.length;
        if (n == 0 || n > MAX_APPROVERS || threshold == 0 || threshold > n) revert BadThreshold();
        if (burnBps > MAX_BURN_BPS) revert BadBurnBps();

        poolId = ++poolCount;
        for (uint256 i; i < n; ++i) {
            address a = approvers[i];
            if (a == address(0) || isApprover[poolId][a]) revert BadApprover();
            isApprover[poolId][a] = true;
            _approvers[poolId].push(a);
        }

        Pool storage p = _pools[poolId];
        p.funder = msg.sender;
        p.burnBps = burnBps;
        p.threshold = threshold;
        p.createdAt = uint64(block.timestamp);
        p.uri = uri;

        _pull(msg.sender, amount);
        p.available = amount;
        p.totalDeposited = amount;
        totalLocked += amount;

        emit PoolCreated(poolId, msg.sender, amount, threshold, burnBps, approvers, uri);
    }

    /// @notice 任何人都可以给资助池追加 BEM。
    function topUp(uint256 poolId, uint256 amount) external nonReentrant poolExists(poolId) {
        if (amount == 0) revert ZeroAmount();
        _pull(msg.sender, amount);
        Pool storage p = _pools[poolId];
        p.available += amount;
        p.totalDeposited += amount;
        totalLocked += amount;
        emit ToppedUp(poolId, msg.sender, amount);
    }

    // ------------------------------------------------------------------ 里程碑
    /// @notice 资助方或审批人从未分配余额中划出一个里程碑。
    /// @param recipient 可直接指定受助人（定向资助）；传 0 地址则开放申请。
    function createMilestone(uint256 poolId, uint256 amount, uint64 deadline, string calldata uri, address recipient)
        external
        poolExists(poolId)
        returns (uint256 id)
    {
        Pool storage p = _pools[poolId];
        if (msg.sender != p.funder && !isApprover[poolId][msg.sender]) revert NotFunderOrApprover();
        if (amount == 0) revert ZeroAmount();
        if (amount > p.available) revert Insufficient();
        if (deadline < block.timestamp + MIN_DEADLINE_DELAY) revert BadDeadline();

        p.available -= amount;
        p.allocated += amount;

        id = ++milestoneCount;
        Milestone storage m = _milestones[id];
        m.poolId = poolId;
        m.amount = amount;
        m.deadline = deadline;
        m.uri = uri;
        if (recipient != address(0)) {
            m.recipient = recipient;
            m.status = MStatus.Awarded;
        } else {
            m.status = MStatus.Open;
        }
        _poolMilestones[poolId].push(id);
        emit MilestoneCreated(poolId, id, msg.sender, amount, deadline, recipient, uri);
        if (recipient != address(0)) emit Awarded(id, type(uint256).max, recipient);
    }

    /// @notice 开发者申请一个开放中的里程碑（申请链接上链，事件可查）。
    function applyFor(uint256 milestoneId, string calldata uri) external returns (uint256 appIndex) {
        Milestone storage m = _ms(milestoneId);
        if (m.status != MStatus.Open) revert BadStatus();
        if (block.timestamp > m.deadline) revert ApplicationsClosed();
        appIndex = _applications[milestoneId].length;
        _applications[milestoneId].push(Application(msg.sender, uint64(block.timestamp), 0, uri));
        emit Applied(milestoneId, appIndex, msg.sender, uri);
    }

    /// @notice 审批人投票选定受助人；同一申请达到 M 票即生效。可改投（旧票自动撤回）。
    function voteAward(uint256 milestoneId, uint256 appIndex) external nonReentrant {
        Milestone storage m = _ms(milestoneId);
        uint256 poolId = m.poolId;
        if (!isApprover[poolId][msg.sender]) revert NotApprover();
        if (m.status != MStatus.Open) revert BadStatus();
        Application[] storage apps = _applications[milestoneId];
        if (appIndex >= apps.length) revert BadApplication();

        uint256 prev = awardVoteOf[milestoneId][msg.sender];
        if (prev == appIndex + 1) revert AlreadyVoted();
        if (prev != 0) {
            apps[prev - 1].awardVotes -= 1;
            emit AwardVoteRevoked(milestoneId, prev - 1, msg.sender);
        }
        awardVoteOf[milestoneId][msg.sender] = appIndex + 1;
        Application storage a = apps[appIndex];
        uint8 v = ++a.awardVotes;
        emit AwardVoted(milestoneId, appIndex, msg.sender, v);

        if (v >= _pools[poolId].threshold) {
            m.recipient = a.applicant;
            m.status = MStatus.Awarded;
            emit Awarded(milestoneId, appIndex, a.applicant);
        }
    }

    /// @notice 受助人提交交付链接（可多次更新）。
    function submitDelivery(uint256 milestoneId, string calldata uri) external {
        Milestone storage m = _ms(milestoneId);
        if (m.status != MStatus.Awarded) revert BadStatus();
        if (msg.sender != m.recipient) revert NotRecipient();
        m.deliveryURI = uri;
        emit DeliverySubmitted(milestoneId, msg.sender, uri);
    }

    /// @notice 审批人投票放款；达到 M 票立即支付（扣除销毁部分）。
    function voteRelease(uint256 milestoneId) external nonReentrant {
        Milestone storage m = _ms(milestoneId);
        uint256 poolId = m.poolId;
        if (!isApprover[poolId][msg.sender]) revert NotApprover();
        if (m.status != MStatus.Awarded) revert BadStatus();
        if (releaseVoted[milestoneId][msg.sender]) revert AlreadyVoted();
        releaseVoted[milestoneId][msg.sender] = true;
        uint8 v = ++m.releaseVotes;
        emit ReleaseVoted(milestoneId, msg.sender, v);

        Pool storage p = _pools[poolId];
        if (v >= p.threshold) {
            uint256 amount = m.amount;
            uint256 burn = amount * p.burnBps / 10_000;
            uint256 pay = amount - burn;
            address to = m.recipient;

            // effects
            m.status = MStatus.Paid;
            p.allocated -= amount;
            p.totalPaid += pay;
            p.totalBurned += burn;
            totalLocked -= amount;
            totalPaid += pay;
            totalBurned += burn;

            // interactions
            if (burn > 0) {
                token.safeTransfer(DEAD, burn);
                emit Burned(poolId, burn);
            }
            token.safeTransfer(to, pay);
            emit Released(poolId, milestoneId, to, amount, pay, burn);
        }
    }

    /// @notice 审批人投票取消未放款的里程碑；达到 M 票后资金退回资金池未分配余额。
    function voteCancel(uint256 milestoneId) external {
        Milestone storage m = _ms(milestoneId);
        uint256 poolId = m.poolId;
        if (!isApprover[poolId][msg.sender]) revert NotApprover();
        if (m.status != MStatus.Open && m.status != MStatus.Awarded) revert BadStatus();
        if (cancelVoted[milestoneId][msg.sender]) revert AlreadyVoted();
        cancelVoted[milestoneId][msg.sender] = true;
        uint8 v = ++m.cancelVotes;
        emit CancelVoted(milestoneId, msg.sender, v);
        if (v >= _pools[poolId].threshold) {
            _returnToPool(m);
            emit MilestoneCancelled(poolId, milestoneId, m.amount);
        }
    }

    /// @notice 申请截止后仍无人获选的里程碑，任何人可标记过期，资金退回资金池。
    function expire(uint256 milestoneId) external {
        Milestone storage m = _ms(milestoneId);
        if (m.status != MStatus.Open) revert BadStatus();
        if (block.timestamp <= m.deadline) revert DeadlineNotPassed();
        _returnToPool(m);
        emit MilestoneExpired(m.poolId, milestoneId, m.amount);
    }

    /// @notice 受助人自愿放弃，资金退回资金池。
    function relinquish(uint256 milestoneId) external {
        Milestone storage m = _ms(milestoneId);
        if (m.status != MStatus.Awarded) revert BadStatus();
        if (msg.sender != m.recipient) revert NotRecipient();
        _returnToPool(m);
        emit Relinquished(m.poolId, milestoneId, msg.sender, m.amount);
    }

    function _returnToPool(Milestone storage m) internal {
        Pool storage p = _pools[m.poolId];
        m.status = MStatus.Cancelled;
        p.allocated -= m.amount;
        p.available += m.amount;
    }

    // ------------------------------------------------------------------ 资助方取回（7 天公示）
    function requestWithdraw(uint256 poolId, uint256 amount) external poolExists(poolId) {
        Pool storage p = _pools[poolId];
        if (msg.sender != p.funder) revert NotFunder();
        if (amount == 0) revert ZeroAmount();
        if (amount > p.available) revert Insufficient();
        uint64 unlockAt = uint64(block.timestamp + WITHDRAW_DELAY);
        p.withdrawAmount = amount;
        p.withdrawUnlockAt = unlockAt;
        emit WithdrawRequested(poolId, amount, unlockAt);
    }

    function cancelWithdraw(uint256 poolId) external poolExists(poolId) {
        Pool storage p = _pools[poolId];
        if (msg.sender != p.funder) revert NotFunder();
        if (p.withdrawUnlockAt == 0) revert NoWithdrawRequest();
        p.withdrawAmount = 0;
        p.withdrawUnlockAt = 0;
        emit WithdrawRequestCancelled(poolId);
    }

    /// @notice 公示期满后执行取回；只能取未分配余额（若期间被分配走，按剩余可用额取回）。
    function executeWithdraw(uint256 poolId) external nonReentrant poolExists(poolId) {
        Pool storage p = _pools[poolId];
        if (msg.sender != p.funder) revert NotFunder();
        if (p.withdrawUnlockAt == 0) revert NoWithdrawRequest();
        if (block.timestamp < p.withdrawUnlockAt) revert TooEarly();
        uint256 amount = p.withdrawAmount < p.available ? p.withdrawAmount : p.available;
        if (amount == 0) revert Insufficient();
        p.withdrawAmount = 0;
        p.withdrawUnlockAt = 0;
        p.available -= amount;
        p.totalWithdrawn += amount;
        totalLocked -= amount;
        token.safeTransfer(p.funder, amount);
        emit Withdrawn(poolId, p.funder, amount);
    }

    // ------------------------------------------------------------------ 只读
    function getPool(uint256 poolId) external view poolExists(poolId) returns (Pool memory pool, address[] memory approvers) {
        return (_pools[poolId], _approvers[poolId]);
    }

    function getApprovers(uint256 poolId) external view returns (address[] memory) {
        return _approvers[poolId];
    }

    function getPoolMilestoneIds(uint256 poolId) external view returns (uint256[] memory) {
        return _poolMilestones[poolId];
    }

    function getMilestone(uint256 milestoneId) external view returns (Milestone memory) {
        if (milestoneId == 0 || milestoneId > milestoneCount) revert NoMilestone();
        return _milestones[milestoneId];
    }

    function applicationCount(uint256 milestoneId) external view returns (uint256) {
        return _applications[milestoneId].length;
    }

    function getApplications(uint256 milestoneId, uint256 offset, uint256 limit) external view returns (Application[] memory out) {
        Application[] storage a = _applications[milestoneId];
        if (offset >= a.length) return out;
        uint256 end = offset + limit > a.length ? a.length : offset + limit;
        out = new Application[](end - offset);
        for (uint256 i = offset; i < end; ++i) out[i - offset] = a[i];
    }

    /// @notice 某审批人对某里程碑的投票情况（前端用）。
    function votesOf(uint256 milestoneId, address approver) external view returns (uint256 awardAppPlus1, bool release, bool cancel) {
        return (awardVoteOf[milestoneId][approver], releaseVoted[milestoneId][approver], cancelVoted[milestoneId][approver]);
    }
}
