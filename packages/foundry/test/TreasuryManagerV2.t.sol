// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/TreasuryManagerV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUniswapV3Pool {
    int24 public currentTick;
    int56[] public tickCumulatives;
    uint160[] public secondsPerLiquidity;

    function setTick(int24 _tick) external {
        currentTick = _tick;
    }

    function setObservations(int56 cumOld, int56 cumNew) external {
        delete tickCumulatives;
        delete secondsPerLiquidity;
        tickCumulatives.push(cumOld);
        tickCumulatives.push(cumNew);
        secondsPerLiquidity.push(0);
        secondsPerLiquidity.push(0);
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (0, currentTick, 0, 0, 0, 0, true);
    }

    function observe(uint32[] calldata)
        external
        view
        returns (int56[] memory, uint160[] memory)
    {
        return (tickCumulatives, secondsPerLiquidity);
    }
}

contract TreasuryManagerV2Test is Test {
    TreasuryManagerV2 public treasury;
    MockERC20 public token;
    MockERC20 public weth;
    MockUniswapV3Pool public pool;

    address public owner = address(0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506);
    address public operator = address(0x1111);
    address public user = address(0x2222);

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH");
        token = new MockERC20("Test Token", "TEST");
        pool = new MockUniswapV3Pool();

        treasury = new TreasuryManagerV2(owner, operator, address(weth));

        // Transfer tokens to treasury
        token.transfer(address(treasury), 100_000_000 * 1e18);

        // Set up pool with normal tick (no circuit breaker trigger)
        // Using tick 0 for both spot and TWAP (price ratio = 1)
        pool.setTick(0);
        // TWAP interval of 86400 seconds (24h)
        // cumOld = 0, cumNew = 0 → TWAP tick = 0
        pool.setObservations(0, 0);
    }

    // ─── Constructor Tests ───────────────────────────────────────────────

    function test_constructor_setsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_constructor_setsOperator() public view {
        assertEq(treasury.operator(), operator);
    }

    function test_constructor_setsWETH() public view {
        assertEq(treasury.weth(), address(weth));
    }

    function test_constructor_revertsZeroOperator() public {
        vm.expectRevert(TreasuryManagerV2.ZeroAddress.selector);
        new TreasuryManagerV2(owner, address(0), address(weth));
    }

    function test_constructor_revertsZeroWETH() public {
        vm.expectRevert(TreasuryManagerV2.ZeroAddress.selector);
        new TreasuryManagerV2(owner, operator, address(0));
    }

    // ─── Admin Tests ─────────────────────────────────────────────────────

    function test_setOperator() public {
        vm.prank(owner);
        treasury.setOperator(address(0x3333));
        assertEq(treasury.operator(), address(0x3333));
    }

    function test_setOperator_revertsNonOwner() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", operator));
        treasury.setOperator(address(0x3333));
    }

    function test_setOperator_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TreasuryManagerV2.ZeroAddress.selector);
        treasury.setOperator(address(0));
    }

    function test_addToken() public {
        vm.prank(owner);
        treasury.addToken(address(token), address(pool), 86400);

        (bool enabled, address tokenPool, uint32 twapInterval,,) = treasury.tokenConfigs(address(token));
        assertTrue(enabled);
        assertEq(tokenPool, address(pool));
        assertEq(twapInterval, 86400);
    }

    function test_addToken_revertsAlreadyEnabled() public {
        vm.startPrank(owner);
        treasury.addToken(address(token), address(pool), 86400);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.TokenAlreadyEnabled.selector, address(token)));
        treasury.addToken(address(token), address(pool), 86400);
        vm.stopPrank();
    }

    function test_addToken_revertsNonOwner() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", operator));
        treasury.addToken(address(token), address(pool), 86400);
    }

    function test_removeToken() public {
        vm.startPrank(owner);
        treasury.addToken(address(token), address(pool), 86400);
        treasury.removeToken(address(token));
        vm.stopPrank();

        (bool enabled,,,,) = treasury.tokenConfigs(address(token));
        assertFalse(enabled);
    }

    function test_setActionConfig() public {
        vm.startPrank(owner);
        treasury.addToken(address(token), address(pool), 86400);
        treasury.setActionConfig(
            address(token),
            TreasuryManagerV2.ActionType.BuybackWETH,
            1000 * 1e18,  // daily cap
            1_000_000,    // daily gas
            true          // enabled
        );
        vm.stopPrank();

        (uint256 dailyCap, uint256 dailyUGas, bool enabled) = treasury.actionConfigs(
            address(token),
            TreasuryManagerV2.ActionType.BuybackWETH
        );
        assertEq(dailyCap, 1000 * 1e18);
        assertEq(dailyUGas, 1_000_000);
        assertTrue(enabled);
    }

    // ─── Withdraw Tests ──────────────────────────────────────────────────

    function test_withdrawETH() public {
        // Fund treasury with ETH
        vm.deal(address(treasury), 10 ether);

        vm.prank(owner);
        treasury.withdrawETH(payable(owner), 5 ether);
        assertEq(address(treasury).balance, 5 ether);
    }

    function test_withdrawETH_revertsNonOwner() public {
        vm.deal(address(treasury), 10 ether);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", operator));
        treasury.withdrawETH(payable(operator), 5 ether);
    }

    function test_withdrawETH_revertsInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.InsufficientBalance.selector, 1 ether, 0));
        treasury.withdrawETH(payable(owner), 1 ether);
    }

    function test_withdrawToken() public {
        vm.prank(owner);
        treasury.withdrawToken(address(token), owner, 1000 * 1e18);
        assertEq(token.balanceOf(owner), 1000 * 1e18);
    }

    function test_withdrawToken_revertsInsufficientBalance() public {
        uint256 balance = token.balanceOf(address(treasury));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.InsufficientBalance.selector, balance + 1, balance));
        treasury.withdrawToken(address(token), owner, balance + 1);
    }

    // ─── Execute Action Tests ────────────────────────────────────────────

    function test_executeAction_basic() public {
        _setupToken();

        vm.prank(operator);
        treasury.executeAction(
            address(token),
            TreasuryManagerV2.ActionType.BuybackWETH,
            100 * 1e18,
            0
        );
    }

    function test_executeAction_revertsNonOperator() public {
        _setupToken();

        vm.prank(user);
        vm.expectRevert(TreasuryManagerV2.OnlyOperator.selector);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
    }

    function test_executeAction_revertsTokenNotEnabled() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.TokenNotEnabled.selector, address(token)));
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
    }

    function test_executeAction_revertsZeroAmount() public {
        _setupToken();

        vm.prank(operator);
        vm.expectRevert(TreasuryManagerV2.ZeroAmount.selector);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 0, 0);
    }

    // ─── Cooldown Tests ──────────────────────────────────────────────────

    function test_cooldown_blocksSecondAction() public {
        _setupToken();

        vm.startPrank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);

        // Try again immediately — should fail
        vm.expectRevert();
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
        vm.stopPrank();
    }

    function test_cooldown_allowsAfterPeriod() public {
        _setupToken();

        vm.startPrank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);

        // Warp past cooldown
        vm.warp(block.timestamp + 4 hours + 1);

        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
        vm.stopPrank();
    }

    function test_getCooldownRemaining() public {
        _setupToken();

        vm.prank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);

        uint256 remaining = treasury.getCooldownRemaining(address(token), TreasuryManagerV2.ActionType.BuybackWETH);
        assertGt(remaining, 0);
        assertLe(remaining, 4 hours);
    }

    // ─── Daily Cap Tests ─────────────────────────────────────────────────

    function test_dailyCap_exceedsRevert() public {
        _setupTokenWithCaps();

        vm.startPrank(operator);
        // Use 800 of 1000 cap
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.Burn, 800 * 1e18, 0);

        // Warp past cooldown
        vm.warp(block.timestamp + 4 hours + 1);

        // Try to use 300 more (only 200 remaining)
        vm.expectRevert();
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.Burn, 300 * 1e18, 0);
        vm.stopPrank();
    }

    function test_dailyCap_resetsNextDay() public {
        _setupTokenWithCaps();

        vm.startPrank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.Burn, 1000 * 1e18, 0);

        // Warp to next day
        vm.warp(block.timestamp + 1 days + 1);

        // Should work again
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.Burn, 1000 * 1e18, 0);
        vm.stopPrank();
    }

    function test_getRemainingDailyCap() public {
        _setupTokenWithCaps();

        uint256 remaining = treasury.getRemainingDailyCap(address(token), TreasuryManagerV2.ActionType.Burn);
        assertEq(remaining, 1000 * 1e18);

        vm.prank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.Burn, 400 * 1e18, 0);

        remaining = treasury.getRemainingDailyCap(address(token), TreasuryManagerV2.ActionType.Burn);
        assertEq(remaining, 600 * 1e18);
    }

    // ─── Buyback Recording Tests ─────────────────────────────────────────

    function test_recordBuyback() public {
        _setupToken();

        vm.prank(operator);
        treasury.recordBuyback(address(token), 1 ether, 1000 * 1e18);

        (,,,uint256 totalETHSpent, uint256 totalTokensReceived) = treasury.tokenConfigs(address(token));
        assertEq(totalETHSpent, 1 ether);
        assertEq(totalTokensReceived, 1000 * 1e18);
    }

    function test_recordBuyback_updatesMarketCap() public {
        _setupToken();

        vm.prank(operator);
        treasury.recordBuyback(address(token), 1 ether, 1000 * 1e18);

        uint256 marketCap = treasury.getMarketCap(address(token));
        // marketCap = (1 ether * 100B) / (1000 * 1e18)
        // = (1e18 * 100_000_000_000) / (1000 * 1e18)
        // = 100_000_000_000 / 1000
        // = 100_000_000 (100M in wei-units)
        assertEq(marketCap, 100_000_000);
    }

    function test_getWeightedAverageCost() public {
        _setupToken();

        vm.prank(operator);
        treasury.recordBuyback(address(token), 2 ether, 1000 * 1e18);

        uint256 wac = treasury.getWeightedAverageCost(address(token));
        // wac = (2 ether * 1e18) / (1000 * 1e18) = 2e18 / 1000 = 2e15
        assertEq(wac, 2e15);
    }

    // ─── Emergency Mode Tests ────────────────────────────────────────────

    function test_triggerEmergency() public {
        _setupToken();

        uint256 balance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        (uint256 triggerTimestamp, bool active) = treasury.emergencyStates(address(token));
        assertTrue(active);
        assertEq(triggerTimestamp, block.timestamp);
        assertEq(treasury.emergencyTriggerSnapshotBalance(address(token)), balance);
    }

    function test_triggerEmergency_operatorCanTrigger() public {
        _setupToken();

        vm.prank(operator);
        treasury.triggerEmergency(address(token));

        (, bool active) = treasury.emergencyStates(address(token));
        assertTrue(active);
    }

    function test_triggerEmergency_revertsAlreadyActive() public {
        _setupToken();

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.EmergencyAlreadyActive.selector, address(token)));
        treasury.triggerEmergency(address(token));
    }

    function test_emergencyAction_day1() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // Max allowed = snapshotBalance * 1 / 25 = 4% of snapshot
        uint256 maxAllowed = snapshotBalance / 25;

        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, maxAllowed);
    }

    function test_emergencyAction_day3() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 3 days
        vm.warp(block.timestamp + 3 days);

        // Max allowed = snapshotBalance * 3 / 25 = 12% of snapshot
        uint256 maxAllowed = (snapshotBalance * 3) / 25;

        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, maxAllowed);
    }

    function test_emergencyAction_day5_fullBalance() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 5 days
        vm.warp(block.timestamp + 5 days);

        // Max allowed = snapshotBalance * 5 / 25 = 20% = full balance (20% × (5/5))
        uint256 maxAllowed = (snapshotBalance * 5) / 25;
        assertEq(maxAllowed, snapshotBalance / 5);

        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, maxAllowed);
    }

    function test_emergencyAction_beyondDay5_capped() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 10 days — should still be capped at 5 days worth
        vm.warp(block.timestamp + 10 days);

        // Max allowed = snapshotBalance * 5 / 25 = 20%
        uint256 maxAllowed = (snapshotBalance * 5) / 25;

        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, maxAllowed);

        // Trying any more should revert (cumulative tracking)
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.EmergencyAllowanceExceeded.selector, maxAllowed + 1, maxAllowed));
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, 1);
    }

    function test_emergencyAction_revertsBeforeDay1() public {
        _setupToken();

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Don't warp — elapsed = 0, elapsedDays = 0, maxAllowed = 0
        // Cumulative used (0) + amount (1) = 1 > maxAllowed (0)
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.EmergencyAllowanceExceeded.selector, 1, 0));
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, 1);
    }

    function test_emergencyAction_revertsNotActive() public {
        _setupToken();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.EmergencyNotActive.selector, address(token)));
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, 100);
    }

    function test_emergencyAction_expiresAfter90Days() public {
        _setupToken();

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp past 90 days
        vm.warp(block.timestamp + 91 days);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreasuryManagerV2.EmergencyNotActive.selector, address(token)));
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, 1);
    }

    function test_deactivateEmergency() public {
        _setupToken();

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        vm.prank(owner);
        treasury.deactivateEmergency(address(token));

        (, bool active) = treasury.emergencyStates(address(token));
        assertFalse(active);
    }

    function test_deactivateEmergency_revertsNonOwner() public {
        _setupToken();

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", operator));
        treasury.deactivateEmergency(address(token));
    }

    function test_getEmergencyAllowance() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // At trigger: 0
        assertEq(treasury.getEmergencyAllowance(address(token)), 0);

        // Day 2
        vm.warp(block.timestamp + 2 days);
        assertEq(treasury.getEmergencyAllowance(address(token)), (snapshotBalance * 2) / 25);

        // Day 5
        vm.warp(block.timestamp + 3 days);
        assertEq(treasury.getEmergencyAllowance(address(token)), (snapshotBalance * 5) / 25);
    }

    function test_emergencyAction_cumulativeTracking() public {
        _setupToken();
        uint256 snapshotBalance = token.balanceOf(address(treasury));

        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 2 days — maxAllowed = snapshotBalance * 2 / 25
        vm.warp(block.timestamp + 2 days);
        uint256 maxAllowed = (snapshotBalance * 2) / 25;

        // Use half
        uint256 halfAllowed = maxAllowed / 2;
        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, halfAllowed);

        // Use most of the remaining
        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, halfAllowed);

        // Should have no allowance left
        uint256 remaining = treasury.getEmergencyAllowance(address(token));
        assertEq(remaining, 0);

        // Any more should fail
        vm.prank(operator);
        vm.expectRevert();
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.Burn, 1);
    }

    // ─── TWAP Circuit Breaker Tests ──────────────────────────────────────

    function test_twapCircuitBreaker_normalConditions() public {
        _setupToken();

        // Pool has equal spot and TWAP ticks — no circuit breaker
        vm.prank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
    }

    function test_twapCircuitBreaker_noPoolSkips() public {
        // Add token without pool
        vm.prank(owner);
        treasury.addToken(address(token), address(0), 0);

        vm.prank(operator);
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);
    }

    function test_emergencyAction_bypassesTWAP() public {
        _setupToken();

        // Set pool to have a very high spot price deviation (>15% above TWAP)
        // Spot tick = 5000 (very high), TWAP tick = 0 (much lower)
        // This creates a >15% price difference
        pool.setTick(5000);
        // For 86400s interval: cumOld = 0, cumNew = 0 → TWAP tick = 0
        pool.setObservations(0, 0);

        // Normal action should fail due to TWAP circuit breaker
        vm.prank(operator);
        vm.expectRevert();
        treasury.executeAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, 100 * 1e18, 0);

        // Trigger emergency
        vm.prank(owner);
        treasury.triggerEmergency(address(token));

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // Emergency action should work (bypasses TWAP)
        uint256 snapshotBalance = treasury.emergencyTriggerSnapshotBalance(address(token));
        uint256 maxAllowed = snapshotBalance / 25;
        vm.prank(operator);
        treasury.executeEmergencyAction(address(token), TreasuryManagerV2.ActionType.BuybackWETH, maxAllowed);
    }

    // ─── Managed Tokens Tests ────────────────────────────────────────────

    function test_getManagedTokens() public {
        vm.startPrank(owner);
        treasury.addToken(address(token), address(pool), 86400);

        MockERC20 token2 = new MockERC20("Token 2", "TK2");
        treasury.addToken(address(token2), address(pool), 86400);
        vm.stopPrank();

        address[] memory tokens = treasury.getManagedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(token));
        assertEq(tokens[1], address(token2));
    }

    function test_getManagedTokenCount() public {
        assertEq(treasury.getManagedTokenCount(), 0);

        vm.prank(owner);
        treasury.addToken(address(token), address(pool), 86400);

        assertEq(treasury.getManagedTokenCount(), 1);
    }

    // ─── Receive ETH Test ────────────────────────────────────────────────

    function test_receiveETH() public {
        vm.deal(user, 10 ether);
        vm.prank(user);
        (bool success,) = address(treasury).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(treasury).balance, 1 ether);
    }

    // ─── Constants Tests ─────────────────────────────────────────────────

    function test_constants() public view {
        assertEq(treasury.MARKET_CAP_SUPPLY(), 100_000_000_000);
        assertEq(treasury.SLIPPAGE_BPS(), 300);
        assertEq(treasury.BPS_DENOMINATOR(), 10_000);
        assertEq(treasury.COOLDOWN_PERIOD(), 4 hours);
        assertEq(treasury.EMERGENCY_DURATION(), 90 days);
        assertEq(treasury.EMERGENCY_VESTING_DAYS(), 5);
        assertEq(treasury.TWAP_DEVIATION_BPS(), 1500);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    function _setupToken() internal {
        vm.prank(owner);
        treasury.addToken(address(token), address(pool), 86400);
    }

    function _setupTokenWithCaps() internal {
        vm.startPrank(owner);
        treasury.addToken(address(token), address(pool), 86400);
        treasury.setActionConfig(
            address(token),
            TreasuryManagerV2.ActionType.Burn,
            1000 * 1e18,  // daily cap: 1000 tokens
            10_000_000,   // daily gas
            true
        );
        vm.stopPrank();
    }
}
