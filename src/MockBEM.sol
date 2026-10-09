// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// 测试网用的 BEM（8 位小数，任何人可 mint）——仅用于测试网 / 单元测试
contract MockBEM is ERC20 {
    constructor() ERC20("Mock BEM", "BEM") {}
    function decimals() public pure override returns (uint8) { return 8; }
    function mint(address to, uint256 a) external { _mint(to, a); }
}

/// 转账收取 1% 手续费的代币（用于测试拒绝 fee-on-transfer）
contract FeeBEM is ERC20 {
    constructor() ERC20("Fee BEM", "fBEM") {}
    function decimals() public pure override returns (uint8) { return 8; }
    function mint(address to, uint256 a) external { _mint(to, a); }
    function _update(address from, address to, uint256 v) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = v / 100;
            super._update(from, address(0), fee);
            v -= fee;
        }
        super._update(from, to, v);
    }
}

/// 转出时尝试重入托管合约的恶意代币（用于测试 ReentrancyGuard）
contract ReentrantBEM is ERC20 {
    address public escrow;
    bytes public payload;
    bool public armed;
    bool public reenterFailed;
    constructor() ERC20("R", "R") {}
    function decimals() public pure override returns (uint8) { return 8; }
    function mint(address to, uint256 a) external { _mint(to, a); }
    function arm(address e, bytes calldata p) external { escrow = e; payload = p; armed = true; }
    function _update(address from, address to, uint256 v) internal override {
        super._update(from, to, v);
        if (armed && from == escrow) {
            armed = false;
            (bool ok,) = escrow.call(payload);
            if (!ok) reenterFailed = true;
        }
    }
}
