// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {GrantEscrow} from "../src/GrantEscrow.sol";
import {MockBEM, FeeBEM, ReentrantBEM} from "../src/MockBEM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GrantEscrowTest is Test {
    GrantEscrow g;
    MockBEM bem;
    address funder = makeAddr("funder");
    address a1 = makeAddr("approver1");
    address a2 = makeAddr("approver2");
    address a3 = makeAddr("approver3");
    address dev = makeAddr("dev");
    address dev2 = makeAddr("dev2");
    address stranger = makeAddr("stranger");
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 constant ONE = 1e8; // 8 位小数

    function setUp() public {
        bem = new MockBEM();
        g = new GrantEscrow(IERC20(address(bem)));
        bem.mint(funder, 100_000 * ONE);
        bem.mint(stranger, 10_000 * ONE);
        vm.prank(funder);
        bem.approve(address(g), type(uint256).max);
        vm.prank(stranger);
        bem.approve(address(g), type(uint256).max);
    }

    function _approvers() internal view returns (address[] memory a) {
        a = new address[](3);
        a[0] = a1; a[1] = a2; a[2] = a3;
    }

    function _pool(uint256 amt, uint16 burnBps) internal returns (uint256) {
        vm.prank(funder);
        return g.createPool(amt, "ipfs://pool", _approvers(), 2, burnBps);
    }

    function _ms(uint256 pid, uint256 amt) internal returns (uint256) {
        vm.prank(funder);
        return g.createMilestone(pid, amt, uint64(block.timestamp + 7 days), "ipfs://m", address(0));
    }

    function _awarded(uint256 pid, uint256 amt) internal returns (uint256 mid) {
        mid = _ms(pid, amt);
        vm.prank(dev);
        g.applyFor(mid, "ipfs://app");
        vm.prank(a1); g.voteAward(mid, 0);
        vm.prank(a2); g.voteAward(mid, 0);
    }

    // ------------------------------------------------------------ 创建资助池
    function test_CreatePool() public {
        uint256 pid = _pool(1000 * ONE, 100);
        assertEq(pid, 1);
        (GrantEscrow.Pool memory p, address[] memory ap) = g.getPool(pid);
        assertEq(p.funder, funder);
        assertEq(p.threshold, 2);
        assertEq(p.burnBps, 100);
        assertEq(p.available, 1000 * ONE);
        assertEq(p.totalDeposited, 1000 * ONE);
        assertEq(ap.length, 3);
        assertTrue(g.isApprover(pid, a2));
        assertFalse(g.isApprover(pid, dev));
        assertEq(bem.balanceOf(address(g)), 1000 * ONE);
        assertEq(g.totalLocked(), 1000 * ONE);
    }

    function test_CreatePool_Reverts() public {
        address[] memory ap = _approvers();
        vm.startPrank(funder);
        vm.expectRevert(GrantEscrow.ZeroAmount.selector);
        g.createPool(0, "", ap, 2, 100);
        vm.expectRevert(GrantEscrow.BadThreshold.selector);
        g.createPool(ONE, "", ap, 0, 100);
        vm.expectRevert(GrantEscrow.BadThreshold.selector);
        g.createPool(ONE, "", ap, 4, 100);
        vm.expectRevert(GrantEscrow.BadThreshold.selector);
        g.createPool(ONE, "", new address[](0), 1, 100);
        vm.expectRevert(GrantEscrow.BadBurnBps.selector);
        g.createPool(ONE, "", ap, 2, 1001);
        address[] memory dup = new address[](2);
        dup[0] = a1; dup[1] = a1;
        vm.expectRevert(GrantEscrow.BadApprover.selector);
        g.createPool(ONE, "", dup, 1, 100);
        address[] memory z = new address[](1);
        vm.expectRevert(GrantEscrow.BadApprover.selector);
        g.createPool(ONE, "", z, 1, 100);
        address[] memory many = new address[](21);
        for (uint256 i; i < 21; ++i) many[i] = address(uint160(i + 100));
        vm.expectRevert(GrantEscrow.BadThreshold.selector);
        g.createPool(ONE, "", many, 2, 100);
        vm.stopPrank();
    }

    function test_MaxBurnAllowed() public {
        uint256 pid = _pool(100 * ONE, 1000);
        uint256 mid = _awarded(pid, 100 * ONE);
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a3); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 90 * ONE);
        assertEq(bem.balanceOf(DEAD), 10 * ONE);
    }

    // ------------------------------------------------------------ 追加资金
    function test_TopUp_Anyone() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.prank(stranger);
        g.topUp(pid, 250 * ONE);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 1250 * ONE);
        assertEq(p.totalDeposited, 1250 * ONE);
        assertEq(g.totalLocked(), 1250 * ONE);
    }

    function test_TopUp_Reverts() public {
        vm.expectRevert(GrantEscrow.NoPool.selector);
        g.topUp(1, ONE);
        uint256 pid = _pool(ONE, 100);
        vm.expectRevert(GrantEscrow.ZeroAmount.selector);
        vm.prank(stranger);
        g.topUp(pid, 0);
    }

    // ------------------------------------------------------------ 完整流程
    function test_HappyPath_1000BEM_2of3_1pctBurn() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 400 * ONE);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 600 * ONE);
        assertEq(p.allocated, 400 * ONE);

        vm.prank(dev);
        uint256 i0 = g.applyFor(mid, "ipfs://dev-proposal");
        vm.prank(dev2);
        uint256 i1 = g.applyFor(mid, "ipfs://dev2-proposal");
        assertEq(i0, 0); assertEq(i1, 1);
        assertEq(g.applicationCount(mid), 2);

        vm.prank(a1); g.voteAward(mid, 0);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Open));
        vm.prank(a3); g.voteAward(mid, 0);
        GrantEscrow.Milestone memory m = g.getMilestone(mid);
        assertEq(uint8(m.status), uint8(GrantEscrow.MStatus.Awarded));
        assertEq(m.recipient, dev);

        vm.prank(dev);
        g.submitDelivery(mid, "https://github.com/x/y");
        assertEq(g.getMilestone(mid).deliveryURI, "https://github.com/x/y");

        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 0);
        vm.prank(a1); g.voteRelease(mid);

        assertEq(bem.balanceOf(dev), 396 * ONE);
        assertEq(bem.balanceOf(DEAD), 4 * ONE);
        m = g.getMilestone(mid);
        assertEq(uint8(m.status), uint8(GrantEscrow.MStatus.Paid));
        (p,) = g.getPool(pid);
        assertEq(p.allocated, 0);
        assertEq(p.available, 600 * ONE);
        assertEq(p.totalPaid, 396 * ONE);
        assertEq(p.totalBurned, 4 * ONE);
        assertEq(g.totalPaid(), 396 * ONE);
        assertEq(g.totalBurned(), 4 * ONE);
        assertEq(g.totalLocked(), 600 * ONE);
        assertEq(bem.balanceOf(address(g)), 600 * ONE);
    }

    function test_DirectGrant_RecipientAtCreation() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.prank(a1); // 审批人也可创建
        uint256 mid = g.createMilestone(pid, 100 * ONE, uint64(block.timestamp + 1 days), "direct", dev);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Awarded));
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 99 * ONE);
    }

    // ------------------------------------------------------------ 8 位小数销毁计算
    function test_BurnMath_8Decimals_Rounding() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 amt = 123_456_789; // 1.23456789 BEM
        uint256 mid = _awarded(pid, amt);
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        uint256 burn = amt * 100 / 10_000; // 1_234_567（向下取整）
        assertEq(burn, 1_234_567);
        assertEq(bem.balanceOf(DEAD), burn);
        assertEq(bem.balanceOf(dev), amt - burn);
    }

    function test_BurnMath_TinyAmount_NoBurn() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 99); // 99 最小单位 -> 销毁 0
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(DEAD), 0);
        assertEq(bem.balanceOf(dev), 99);
    }

    function test_ZeroBurn() public {
        uint256 pid = _pool(1000 * ONE, 0);
        uint256 mid = _awarded(pid, 500 * ONE);
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 500 * ONE);
        assertEq(bem.balanceOf(DEAD), 0);
    }

    function testFuzz_BurnMath(uint256 amt, uint16 bps) public {
        bps = uint16(bound(bps, 0, 1000));
        amt = bound(amt, 1, 100_000 * ONE);
        vm.prank(funder);
        uint256 pid = g.createPool(amt, "", _approvers(), 2, bps);
        uint256 mid = _awarded(pid, amt);
        vm.prank(a2); g.voteRelease(mid);
        vm.prank(a3); g.voteRelease(mid);
        uint256 burn = amt * bps / 10_000;
        assertEq(bem.balanceOf(DEAD), burn);
        assertEq(bem.balanceOf(dev), amt - burn);
        assertEq(bem.balanceOf(DEAD) + bem.balanceOf(dev), amt); // 资金守恒
        assertEq(bem.balanceOf(address(g)), 0);
    }

    // ------------------------------------------------------------ M-of-N
    function test_Release_NeedsThreshold() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 100 * ONE);
        vm.prank(a3); g.voteRelease(mid);
        assertEq(g.getMilestone(mid).releaseVotes, 1);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Awarded));
        assertEq(bem.balanceOf(dev), 0);
    }

    function test_3of3_Threshold() public {
        vm.prank(funder);
        uint256 pid = g.createPool(1000 * ONE, "", _approvers(), 3, 100);
        uint256 mid = _ms(pid, 100 * ONE);
        vm.prank(dev); g.applyFor(mid, "x");
        vm.prank(a1); g.voteAward(mid, 0);
        vm.prank(a2); g.voteAward(mid, 0);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Open));
        vm.prank(a3); g.voteAward(mid, 0);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Awarded));
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 0);
        vm.prank(a3); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 99 * ONE);
    }

    function test_1of1_Threshold() public {
        address[] memory ap = new address[](1);
        ap[0] = a1;
        vm.prank(funder);
        uint256 pid = g.createPool(10 * ONE, "", ap, 1, 100);
        uint256 mid = _ms(pid, 10 * ONE);
        vm.prank(dev); g.applyFor(mid, "x");
        vm.prank(a1); g.voteAward(mid, 0);
        vm.prank(a1); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 9.9e8);
    }

    function test_AwardSplitVotes_ThenChange() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 100 * ONE);
        vm.prank(dev); g.applyFor(mid, "a");
        vm.prank(dev2); g.applyFor(mid, "b");
        vm.prank(a1); g.voteAward(mid, 0);
        vm.prank(a2); g.voteAward(mid, 1);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Open));
        // a1 改投 1 -> dev2 达到 2 票
        vm.prank(a1); g.voteAward(mid, 1);
        GrantEscrow.Milestone memory m = g.getMilestone(mid);
        assertEq(m.recipient, dev2);
        GrantEscrow.Application[] memory apps = g.getApplications(mid, 0, 10);
        assertEq(apps.length, 2);
        assertEq(apps[0].awardVotes, 0);
        assertEq(apps[1].awardVotes, 2);
        (uint256 av,,) = g.votesOf(mid, a1);
        assertEq(av, 2);
    }

    // ------------------------------------------------------------ 重复投票 / 非审批人
    function test_DoubleVote_Reverts() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 100 * ONE);
        vm.prank(dev); g.applyFor(mid, "a");
        vm.prank(a1); g.voteAward(mid, 0);
        vm.prank(a1);
        vm.expectRevert(GrantEscrow.AlreadyVoted.selector);
        g.voteAward(mid, 0);
        vm.prank(a2); g.voteAward(mid, 0);

        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a1);
        vm.expectRevert(GrantEscrow.AlreadyVoted.selector);
        g.voteRelease(mid);

        vm.prank(a3); g.voteCancel(mid);
        vm.prank(a3);
        vm.expectRevert(GrantEscrow.AlreadyVoted.selector);
        g.voteCancel(mid);
    }

    function test_NonApprover_Reverts() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 100 * ONE);
        vm.prank(dev); g.applyFor(mid, "a");
        vm.startPrank(funder); // 资助方不是审批人
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteAward(mid, 0);
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteRelease(mid);
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteCancel(mid);
        vm.stopPrank();
        vm.prank(dev);
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteRelease(mid);
        vm.prank(stranger);
        vm.expectRevert(GrantEscrow.NotFunderOrApprover.selector);
        g.createMilestone(pid, ONE, uint64(block.timestamp + 1 days), "", address(0));
    }

    function test_ApproverOfOtherPool_Cannot() public {
        uint256 pid1 = _pool(1000 * ONE, 100);
        address[] memory ap = new address[](1);
        ap[0] = stranger;
        vm.prank(stranger);
        g.createPool(10 * ONE, "", ap, 1, 100);
        uint256 mid = _awarded(pid1, 100 * ONE);
        vm.prank(stranger);
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteRelease(mid);
    }

    function test_ReleaseBeforeAward_Reverts() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 100 * ONE);
        vm.prank(a1);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.voteRelease(mid);
    }

    function test_NoDoublePay() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 100 * ONE);
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        vm.prank(a3);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.voteRelease(mid);
        vm.prank(a3);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.voteCancel(mid);
        assertEq(bem.balanceOf(dev), 99 * ONE);
    }

    // ------------------------------------------------------------ 申请
    function test_Apply_Reverts() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.expectRevert(GrantEscrow.NoMilestone.selector);
        g.applyFor(99, "x");
        uint256 mid = _ms(pid, 100 * ONE);
        vm.warp(block.timestamp + 8 days);
        vm.prank(dev);
        vm.expectRevert(GrantEscrow.ApplicationsClosed.selector);
        g.applyFor(mid, "x");
        uint256 mid2 = _awarded(pid, 10 * ONE);
        vm.prank(dev2);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.applyFor(mid2, "late");
        uint256 mid3 = _ms(pid, 10 * ONE);
        vm.prank(a3);
        vm.expectRevert(GrantEscrow.BadApplication.selector);
        g.voteAward(mid3, 0); // 还没有申请
    }

    function test_CreateMilestone_Reverts() public {
        uint256 pid = _pool(100 * ONE, 100);
        vm.startPrank(funder);
        vm.expectRevert(GrantEscrow.Insufficient.selector);
        g.createMilestone(pid, 101 * ONE, uint64(block.timestamp + 1 days), "", address(0));
        vm.expectRevert(GrantEscrow.ZeroAmount.selector);
        g.createMilestone(pid, 0, uint64(block.timestamp + 1 days), "", address(0));
        vm.expectRevert(GrantEscrow.BadDeadline.selector);
        g.createMilestone(pid, ONE, uint64(block.timestamp + 10), "", address(0));
        vm.expectRevert(GrantEscrow.NoPool.selector);
        g.createMilestone(9, ONE, uint64(block.timestamp + 1 days), "", address(0));
        vm.stopPrank();
    }

    function test_SubmitDelivery_OnlyRecipient() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 100 * ONE);
        vm.prank(dev2);
        vm.expectRevert(GrantEscrow.NotRecipient.selector);
        g.submitDelivery(mid, "x");
    }

    // ------------------------------------------------------------ 取消
    function test_Cancel_Awarded_ReturnsToPool() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 300 * ONE);
        vm.prank(a1); g.voteRelease(mid); // 只有 1 票放款
        vm.prank(a2); g.voteCancel(mid);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Awarded));
        vm.prank(a3); g.voteCancel(mid);
        assertEq(uint8(g.getMilestone(mid).status), uint8(GrantEscrow.MStatus.Cancelled));
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 1000 * ONE);
        assertEq(p.allocated, 0);
        assertEq(bem.balanceOf(dev), 0);
        assertEq(g.totalLocked(), 1000 * ONE);
        vm.prank(a2);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.voteRelease(mid);
    }

    function test_Cancel_Open() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 300 * ONE);
        vm.prank(a1); g.voteCancel(mid);
        vm.prank(a2); g.voteCancel(mid);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 1000 * ONE);
        vm.prank(dev);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.applyFor(mid, "x");
    }

    function test_FunderCannotCancelAllocated() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 300 * ONE);
        vm.startPrank(funder);
        vm.expectRevert(GrantEscrow.NotApprover.selector);
        g.voteCancel(mid);
        // 只能申请取回未分配的 700
        vm.expectRevert(GrantEscrow.Insufficient.selector);
        g.requestWithdraw(pid, 701 * ONE);
        vm.stopPrank();
    }

    function test_Expire_OpenAfterDeadline() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 300 * ONE);
        vm.expectRevert(GrantEscrow.DeadlineNotPassed.selector);
        g.expire(mid);
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(stranger);
        g.expire(mid);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 1000 * ONE);
    }

    function test_Expire_AwardedNotAllowed() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 300 * ONE);
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(GrantEscrow.BadStatus.selector);
        g.expire(mid);
        // 过期后受助人仍可被放款
        vm.prank(a1); g.voteRelease(mid);
        vm.prank(a2); g.voteRelease(mid);
        assertEq(bem.balanceOf(dev), 297 * ONE);
    }

    function test_Relinquish() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _awarded(pid, 300 * ONE);
        vm.prank(dev2);
        vm.expectRevert(GrantEscrow.NotRecipient.selector);
        g.relinquish(mid);
        vm.prank(dev);
        g.relinquish(mid);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 1000 * ONE);
    }

    // ------------------------------------------------------------ 资助方取回（时间锁）
    function test_Withdraw_Timelock() public {
        uint256 pid = _pool(1000 * ONE, 100);
        _awarded(pid, 300 * ONE);
        vm.prank(funder);
        g.requestWithdraw(pid, 700 * ONE);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.TooEarly.selector);
        g.executeWithdraw(pid);
        vm.warp(block.timestamp + 7 days - 1);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.TooEarly.selector);
        g.executeWithdraw(pid);
        vm.warp(block.timestamp + 1);
        uint256 before = bem.balanceOf(funder);
        vm.prank(funder);
        g.executeWithdraw(pid);
        assertEq(bem.balanceOf(funder) - before, 700 * ONE);
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(p.available, 0);
        assertEq(p.allocated, 300 * ONE);
        assertEq(p.totalWithdrawn, 700 * ONE);
        assertEq(p.withdrawUnlockAt, 0);
        assertEq(bem.balanceOf(address(g)), 300 * ONE); // 已分配的资金仍在
        assertEq(g.totalLocked(), 300 * ONE);
    }

    function test_Withdraw_CappedByAvailableAtExecution() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.prank(funder);
        g.requestWithdraw(pid, 1000 * ONE);
        _awarded(pid, 400 * ONE); // 公示期内又分配了 400
        vm.warp(block.timestamp + 7 days);
        vm.prank(funder);
        g.executeWithdraw(pid);
        assertEq(bem.balanceOf(address(g)), 400 * ONE);
    }

    function test_Withdraw_OnlyFunder_AndCancel() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.prank(a1);
        vm.expectRevert(GrantEscrow.NotFunder.selector);
        g.requestWithdraw(pid, ONE);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.NoWithdrawRequest.selector);
        g.executeWithdraw(pid);
        vm.prank(funder);
        g.requestWithdraw(pid, 100 * ONE);
        vm.prank(stranger);
        vm.expectRevert(GrantEscrow.NotFunder.selector);
        g.executeWithdraw(pid);
        vm.prank(funder);
        g.cancelWithdraw(pid);
        vm.warp(block.timestamp + 8 days);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.NoWithdrawRequest.selector);
        g.executeWithdraw(pid);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.ZeroAmount.selector);
        g.requestWithdraw(pid, 0);
    }

    function test_Withdraw_NewRequestResetsTimer() public {
        uint256 pid = _pool(1000 * ONE, 100);
        vm.prank(funder);
        g.requestWithdraw(pid, 100 * ONE);
        vm.warp(block.timestamp + 6 days);
        vm.prank(funder);
        g.requestWithdraw(pid, 200 * ONE);
        vm.warp(block.timestamp + 2 days);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.TooEarly.selector);
        g.executeWithdraw(pid);
    }

    // ------------------------------------------------------------ fee-on-transfer & 重入
    function test_RejectFeeOnTransfer() public {
        FeeBEM f = new FeeBEM();
        GrantEscrow g2 = new GrantEscrow(IERC20(address(f)));
        f.mint(funder, 1000 * ONE);
        vm.startPrank(funder);
        f.approve(address(g2), type(uint256).max);
        vm.expectRevert(GrantEscrow.FeeOnTransferNotSupported.selector);
        g2.createPool(100 * ONE, "", _approvers(), 2, 100);
        vm.stopPrank();
    }

    function test_Reentrancy_OnRelease() public {
        ReentrantBEM r = new ReentrantBEM();
        GrantEscrow g2 = new GrantEscrow(IERC20(address(r)));
        r.mint(funder, 1000 * ONE);
        vm.startPrank(funder);
        r.approve(address(g2), type(uint256).max);
        uint256 pid = g2.createPool(1000 * ONE, "", _approvers(), 2, 100);
        uint256 mid = g2.createMilestone(pid, 500 * ONE, uint64(block.timestamp + 1 days), "", dev);
        vm.stopPrank();
        // 代币在转出时尝试重入 voteRelease
        r.arm(address(g2), abi.encodeCall(GrantEscrow.voteRelease, (mid)));
        vm.prank(a1); g2.voteRelease(mid);
        vm.prank(a2); g2.voteRelease(mid);
        assertTrue(r.reenterFailed());
        assertEq(r.balanceOf(dev), 495 * ONE);
        assertEq(r.balanceOf(address(g2)), 500 * ONE);
    }

    function test_Reentrancy_OnWithdraw() public {
        ReentrantBEM r = new ReentrantBEM();
        GrantEscrow g2 = new GrantEscrow(IERC20(address(r)));
        r.mint(funder, 1000 * ONE);
        vm.startPrank(funder);
        r.approve(address(g2), type(uint256).max);
        uint256 pid = g2.createPool(1000 * ONE, "", _approvers(), 2, 100);
        g2.requestWithdraw(pid, 100 * ONE);
        vm.stopPrank();
        vm.warp(block.timestamp + 7 days);
        r.arm(address(g2), abi.encodeCall(GrantEscrow.executeWithdraw, (pid)));
        vm.prank(funder);
        g2.executeWithdraw(pid);
        assertTrue(r.reenterFailed());
        assertEq(r.balanceOf(address(g2)), 900 * ONE);
    }

    // ------------------------------------------------------------ 多池隔离 & 视图
    function test_PoolsIsolated() public {
        uint256 p1 = _pool(100 * ONE, 100);
        uint256 p2 = _pool(200 * ONE, 100);
        vm.prank(funder);
        vm.expectRevert(GrantEscrow.Insufficient.selector);
        g.createMilestone(p1, 150 * ONE, uint64(block.timestamp + 1 days), "", address(0));
        uint256 m2 = _ms(p2, 150 * ONE);
        uint256[] memory ids = g.getPoolMilestoneIds(p2);
        assertEq(ids.length, 1);
        assertEq(ids[0], m2);
        assertEq(g.getPoolMilestoneIds(p1).length, 0);
    }

    function test_GetApplications_Pagination() public {
        uint256 pid = _pool(1000 * ONE, 100);
        uint256 mid = _ms(pid, 10 * ONE);
        for (uint256 i; i < 5; ++i) {
            vm.prank(address(uint160(1000 + i)));
            g.applyFor(mid, "x");
        }
        assertEq(g.getApplications(mid, 3, 10).length, 2);
        assertEq(g.getApplications(mid, 9, 10).length, 0);
        assertEq(g.getApplications(mid, 1, 2)[1].applicant, address(uint160(1002)));
    }

    function test_Views_Revert_Unknown() public {
        vm.expectRevert(GrantEscrow.NoPool.selector);
        g.getPool(1);
        vm.expectRevert(GrantEscrow.NoMilestone.selector);
        g.getMilestone(1);
    }

    /// 资金守恒：合约余额 == 各池 available + allocated
    function testFuzz_Accounting(uint96 a, uint96 b, uint96 c, bool cancel) public {
        uint256 amt = bound(a, 3, 50_000 * ONE);
        uint256 m1 = bound(b, 1, amt / 3);
        uint256 top = bound(c, 1, 10_000 * ONE);
        uint256 pid = _pool(amt, 250);
        vm.prank(stranger); g.topUp(pid, top);
        uint256 mid = _awarded(pid, m1);
        if (cancel) {
            vm.prank(a1); g.voteCancel(mid);
            vm.prank(a2); g.voteCancel(mid);
        } else {
            vm.prank(a1); g.voteRelease(mid);
            vm.prank(a2); g.voteRelease(mid);
        }
        (GrantEscrow.Pool memory p,) = g.getPool(pid);
        assertEq(bem.balanceOf(address(g)), p.available + p.allocated);
        assertEq(g.totalLocked(), p.available + p.allocated);
        assertEq(p.totalDeposited, p.available + p.allocated + p.totalPaid + p.totalBurned + p.totalWithdrawn);
    }
}
