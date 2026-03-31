// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TreasuryManagerV2 — Market Cap Treasury Management
/// @notice Manages treasury operations with market cap calculations, daily caps,
///         cooldowns, slippage protection, TWAP circuit breaker, and 90-day emergency mode
/// @dev Owner is the client (0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506)
contract TreasuryManagerV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────
    uint256 public constant MARKET_CAP_SUPPLY = 100_000_000_000; // 100B tokens
    uint256 public constant SLIPPAGE_BPS = 300; // 3%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant COOLDOWN_PERIOD = 4 hours;
    uint256 public constant EMERGENCY_DURATION = 90 days;
    uint256 public constant EMERGENCY_VESTING_DAYS = 5;
    uint256 public constant TWAP_DEVIATION_BPS = 1500; // 15%

    // ─── Enums ───────────────────────────────────────────────────────────
    enum ActionType {
        BuybackWETH,    // 0
        BuybackUSDC,    // 1
        Burn,           // 2
        Stake,          // 3
        RebalanceWETH,  // 4
        RebalanceUSDC   // 5
    }

    // ─── Structs ─────────────────────────────────────────────────────────
    struct TokenConfig {
        bool enabled;
        address pool;               // Uniswap V3 pool for TWAP
        uint32 twapInterval;        // TWAP observation window (seconds)
        uint256 totalETHSpent;      // Total ETH spent buying this token
        uint256 totalTokensReceived; // Total tokens received from buys
    }

    struct ActionConfig {
        uint256 dailyCap;           // Max amount per day (in token units)
        uint256 dailyUGas;          // Max gas units per day
        bool enabled;
    }

    struct DailyUsage {
        uint256 amountUsed;
        uint256 gasUsed;
        uint256 resetTimestamp;     // Start of current day window
    }

    struct EmergencyState {
        uint256 triggerTimestamp;
        bool active;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public operator;
    address public weth;

    // Token configs
    mapping(address => TokenConfig) public tokenConfigs;
    address[] public managedTokens;

    // Per-token per-action configs
    mapping(address => mapping(ActionType => ActionConfig)) public actionConfigs;

    // Per-token per-action daily usage
    mapping(address => mapping(ActionType => DailyUsage)) public dailyUsage;

    // Per-token last action timestamp (cooldown)
    mapping(address => mapping(ActionType => uint256)) public lastActionTime;

    // Emergency state per token
    mapping(address => EmergencyState) public emergencyStates;
    mapping(address => uint256) public emergencyTriggerSnapshotBalance;
    mapping(address => uint256) public emergencyAmountUsed; // Cumulative amount used in emergency

    // ─── Events ──────────────────────────────────────────────────────────
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event TokenAdded(address indexed token, address pool, uint32 twapInterval);
    event TokenRemoved(address indexed token);
    event ActionConfigUpdated(address indexed token, ActionType actionType, uint256 dailyCap, uint256 dailyUGas);
    event ActionExecuted(
        address indexed token,
        ActionType actionType,
        uint256 amount,
        uint256 marketCap,
        uint256 timestamp
    );
    event BuybackExecuted(
        address indexed token,
        uint256 ethSpent,
        uint256 tokensReceived,
        uint256 newMarketCap
    );
    event EmergencyTriggered(address indexed token, uint256 snapshotBalance, uint256 timestamp);
    event EmergencyActionExecuted(
        address indexed token,
        ActionType actionType,
        uint256 amount,
        uint256 elapsed,
        uint256 maxAllowed
    );
    event EmergencyDeactivated(address indexed token);
    event TokenPoolUpdated(address indexed token, address pool, uint32 twapInterval);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────
    error OnlyOperator();
    error OnlyOwnerOrOperator();
    error TokenNotEnabled(address token);
    error TokenAlreadyEnabled(address token);
    error CooldownNotElapsed(address token, ActionType actionType, uint256 remaining);
    error DailyCapExceeded(address token, ActionType actionType, uint256 requested, uint256 remaining);
    error DailyGasExceeded(address token, ActionType actionType, uint256 requested, uint256 remaining);
    error SlippageExceeded(uint256 expected, uint256 actual);
    error TWAPCircuitBreakerTriggered(uint256 spotPrice, uint256 twapPrice, uint256 deviationBps);
    error EmergencyNotActive(address token);
    error EmergencyAlreadyActive(address token);
    error EmergencyNotEligible(address token);
    error EmergencyAllowanceExceeded(uint256 requested, uint256 allowed);
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    modifier onlyOwnerOrOperator() {
        if (msg.sender != owner() && msg.sender != operator) revert OnlyOwnerOrOperator();
        _;
    }

    modifier tokenEnabled(address token) {
        if (!tokenConfigs[token].enabled) revert TokenNotEnabled(token);
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @param _owner The client address that owns this contract
    /// @param _operator The operator address that executes treasury actions
    /// @param _weth WETH contract address
    constructor(
        address _owner,
        address _operator,
        address _weth
    ) Ownable(_owner) {
        if (_operator == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        operator = _operator;
        weth = _weth;
    }

    // ─── Admin Functions (Owner Only) ────────────────────────────────────

    /// @notice Set a new operator
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        emit OperatorUpdated(operator, _operator);
        operator = _operator;
    }

    /// @notice Add a token to manage
    function addToken(
        address token,
        address pool,
        uint32 twapInterval
    ) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (tokenConfigs[token].enabled) revert TokenAlreadyEnabled(token);
        
        tokenConfigs[token] = TokenConfig({
            enabled: true,
            pool: pool,
            twapInterval: twapInterval,
            totalETHSpent: 0,
            totalTokensReceived: 0
        });
        managedTokens.push(token);

        emit TokenAdded(token, pool, twapInterval);
    }

    /// @notice Remove a managed token
    function removeToken(address token) external onlyOwner tokenEnabled(token) {
        tokenConfigs[token].enabled = false;

        // Remove from managedTokens array
        for (uint256 i = 0; i < managedTokens.length; i++) {
            if (managedTokens[i] == token) {
                managedTokens[i] = managedTokens[managedTokens.length - 1];
                managedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /// @notice Configure daily caps and gas limits for an action type on a token
    function setActionConfig(
        address token,
        ActionType actionType,
        uint256 dailyCap,
        uint256 dailyUGas,
        bool enabled
    ) external onlyOwner tokenEnabled(token) {
        actionConfigs[token][actionType] = ActionConfig({
            dailyCap: dailyCap,
            dailyUGas: dailyUGas,
            enabled: enabled
        });

        emit ActionConfigUpdated(token, actionType, dailyCap, dailyUGas);
    }

    /// @notice Update the pool address for TWAP lookups
    function setTokenPool(address token, address pool, uint32 twapInterval) external onlyOwner tokenEnabled(token) {
        tokenConfigs[token].pool = pool;
        tokenConfigs[token].twapInterval = twapInterval;
        emit TokenPoolUpdated(token, pool, twapInterval);
    }

    /// @notice Withdraw ETH (owner only)
    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance(amount, address(this).balance);
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
        emit ETHWithdrawn(to, amount);
    }

    /// @notice Withdraw tokens (owner only)
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(amount, balance);
        
        IERC20(token).safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    // ─── Path 2: Market Cap Operations (Operator) ────────────────────────

    /// @notice Execute a treasury action under Path 2 (Market Cap)
    /// @param token The token to operate on
    /// @param actionType The type of action
    /// @param amount The amount of tokens for this action
    /// @param gasEstimate Estimated gas for this operation (for daily gas tracking)
    function executeAction(
        address token,
        ActionType actionType,
        uint256 amount,
        uint256 gasEstimate
    ) external onlyOperator nonReentrant tokenEnabled(token) {
        if (amount == 0) revert ZeroAmount();

        // Check TWAP circuit breaker (Path 1 & 2 only, not Path 3 emergency)
        if (!emergencyStates[token].active) {
            _checkTWAPCircuitBreaker(token);
        }

        // Check cooldown
        _checkCooldown(token, actionType);

        // Check and update daily caps
        _checkAndUpdateDailyCaps(token, actionType, amount, gasEstimate);

        // Calculate market cap for event
        uint256 marketCap = getMarketCap(token);

        // Update cooldown
        lastActionTime[token][actionType] = block.timestamp;

        emit ActionExecuted(token, actionType, amount, marketCap, block.timestamp);
    }

    /// @notice Record a token buyback with ETH
    /// @param token The token bought
    /// @param ethSpent ETH spent on the buyback
    /// @param tokensReceived Tokens received
    function recordBuyback(
        address token,
        uint256 ethSpent,
        uint256 tokensReceived
    ) external onlyOperator tokenEnabled(token) {
        if (ethSpent == 0 || tokensReceived == 0) revert ZeroAmount();

        tokenConfigs[token].totalETHSpent += ethSpent;
        tokenConfigs[token].totalTokensReceived += tokensReceived;

        uint256 newMarketCap = getMarketCap(token);
        emit BuybackExecuted(token, ethSpent, tokensReceived, newMarketCap);
    }

    // ─── Path 3: 90-Day Emergency Mode ───────────────────────────────────

    /// @notice Trigger emergency mode for a token (owner or operator)
    /// @dev Snapshots the token balance on first trigger
    function triggerEmergency(address token) external onlyOwnerOrOperator tokenEnabled(token) {
        if (emergencyStates[token].active) revert EmergencyAlreadyActive(token);

        uint256 balance = IERC20(token).balanceOf(address(this));
        emergencyStates[token] = EmergencyState({
            triggerTimestamp: block.timestamp,
            active: true
        });
        emergencyTriggerSnapshotBalance[token] = balance;
        emergencyAmountUsed[token] = 0;

        emit EmergencyTriggered(token, balance, block.timestamp);
    }

    /// @notice Execute an action under emergency mode
    /// @dev No ROI check, no market cap check, no TWAP circuit breaker
    ///      Limited to 20% of snapshot balance per 24 hours elapsed since trigger
    ///      20% after 5 days = full balance
    function executeEmergencyAction(
        address token,
        ActionType actionType,
        uint256 amount
    ) external onlyOperator nonReentrant tokenEnabled(token) {
        EmergencyState storage es = emergencyStates[token];
        if (!es.active) revert EmergencyNotActive(token);
        if (amount == 0) revert ZeroAmount();

        // Check if emergency period has expired (90 days)
        if (block.timestamp > es.triggerTimestamp + EMERGENCY_DURATION) {
            es.active = false;
            emit EmergencyDeactivated(token);
            revert EmergencyNotActive(token);
        }

        // Calculate allowed amount: 20% × (min(elapsed_days, 5) / 5) of snapshot balance
        uint256 elapsed = block.timestamp - es.triggerTimestamp;
        uint256 elapsedDays = elapsed / 1 days;
        if (elapsedDays > EMERGENCY_VESTING_DAYS) {
            elapsedDays = EMERGENCY_VESTING_DAYS;
        }

        uint256 snapshotBalance = emergencyTriggerSnapshotBalance[token];
        // 20% × (min(elapsed, 5) / 5) = 20% × elapsedDays / 5
        // = snapshotBalance × 20 × elapsedDays / (100 × 5)
        // = snapshotBalance × elapsedDays / 25
        uint256 maxAllowed = (snapshotBalance * elapsedDays) / 25;

        // Track cumulative usage
        uint256 totalUsedAfter = emergencyAmountUsed[token] + amount;
        if (totalUsedAfter > maxAllowed) revert EmergencyAllowanceExceeded(totalUsedAfter, maxAllowed);

        emergencyAmountUsed[token] = totalUsedAfter;

        // No cooldown check, no daily caps, no TWAP check in emergency
        // Update last action time for tracking
        lastActionTime[token][actionType] = block.timestamp;

        emit EmergencyActionExecuted(token, actionType, amount, elapsed, maxAllowed);
    }

    /// @notice Deactivate emergency mode for a token (owner only)
    function deactivateEmergency(address token) external onlyOwner {
        if (!emergencyStates[token].active) revert EmergencyNotActive(token);
        emergencyStates[token].active = false;
        emit EmergencyDeactivated(token);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Calculate the market cap for a token
    /// @dev Market Cap = (Total ETH Spent / Total Tokens Received) × 100B / 1e18
    ///      This represents: weighted average cost per token × total supply
    function getMarketCap(address token) public view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (config.totalTokensReceived == 0) return 0;

        // marketCap = (totalETHSpent * MARKET_CAP_SUPPLY) / (totalTokensReceived)
        // All values in wei (1e18), result in wei
        return (config.totalETHSpent * MARKET_CAP_SUPPLY) / config.totalTokensReceived;
    }

    /// @notice Get the weighted average cost in ETH per token
    function getWeightedAverageCost(address token) public view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (config.totalTokensReceived == 0) return 0;
        return (config.totalETHSpent * 1e18) / config.totalTokensReceived;
    }

    /// @notice Get the remaining daily cap for a token/action
    function getRemainingDailyCap(address token, ActionType actionType) public view returns (uint256) {
        ActionConfig storage config = actionConfigs[token][actionType];
        DailyUsage storage usage = dailyUsage[token][actionType];

        if (!config.enabled) return 0;

        // Reset if new day
        if (block.timestamp >= usage.resetTimestamp + 1 days) {
            return config.dailyCap;
        }

        if (usage.amountUsed >= config.dailyCap) return 0;
        return config.dailyCap - usage.amountUsed;
    }

    /// @notice Get remaining daily gas for a token/action
    function getRemainingDailyGas(address token, ActionType actionType) public view returns (uint256) {
        ActionConfig storage config = actionConfigs[token][actionType];
        DailyUsage storage usage = dailyUsage[token][actionType];

        if (!config.enabled) return 0;

        if (block.timestamp >= usage.resetTimestamp + 1 days) {
            return config.dailyUGas;
        }

        if (usage.gasUsed >= config.dailyUGas) return 0;
        return config.dailyUGas - usage.gasUsed;
    }

    /// @notice Get the remaining emergency allowance for a token
    function getEmergencyAllowance(address token) public view returns (uint256) {
        EmergencyState storage es = emergencyStates[token];
        if (!es.active) return 0;

        uint256 elapsed = block.timestamp - es.triggerTimestamp;
        uint256 elapsedDays = elapsed / 1 days;
        if (elapsedDays > EMERGENCY_VESTING_DAYS) {
            elapsedDays = EMERGENCY_VESTING_DAYS;
        }

        uint256 totalAllowed = (emergencyTriggerSnapshotBalance[token] * elapsedDays) / 25;
        uint256 used = emergencyAmountUsed[token];
        if (used >= totalAllowed) return 0;
        return totalAllowed - used;
    }

    /// @notice Get time remaining until cooldown ends
    function getCooldownRemaining(address token, ActionType actionType) public view returns (uint256) {
        uint256 lastAction = lastActionTime[token][actionType];
        if (lastAction == 0) return 0;

        uint256 cooldownEnd = lastAction + COOLDOWN_PERIOD;
        if (block.timestamp >= cooldownEnd) return 0;
        return cooldownEnd - block.timestamp;
    }

    /// @notice Get list of all managed tokens
    function getManagedTokens() external view returns (address[] memory) {
        return managedTokens;
    }

    /// @notice Get the count of managed tokens
    function getManagedTokenCount() external view returns (uint256) {
        return managedTokens.length;
    }

    // ─── Internal Functions ──────────────────────────────────────────────

    /// @dev Check TWAP circuit breaker — blocks if spot >15% above TWAP
    function _checkTWAPCircuitBreaker(address token) internal view {
        TokenConfig storage config = tokenConfigs[token];
        if (config.pool == address(0)) return; // No pool configured, skip check

        // Get spot price and TWAP from the Uniswap V3 pool
        (uint256 spotPrice, uint256 twapPrice) = _getPrices(config.pool, config.twapInterval);

        if (twapPrice == 0) return; // No TWAP data available yet

        // Check if spot > TWAP * 1.15 (i.e., spot more than 15% above TWAP)
        uint256 maxSpot = (twapPrice * (BPS_DENOMINATOR + TWAP_DEVIATION_BPS)) / BPS_DENOMINATOR;
        if (spotPrice > maxSpot) {
            revert TWAPCircuitBreakerTriggered(spotPrice, twapPrice, TWAP_DEVIATION_BPS);
        }
    }

    /// @dev Get spot price and TWAP from a Uniswap V3 pool
    function _getPrices(address pool, uint32 twapInterval) internal view returns (uint256 spotPrice, uint256 twapPrice) {
        // Get current tick (spot price)
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

        // Get TWAP tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativeDiff = tickCumulatives[1] - tickCumulatives[0];
        int24 twapTick = int24(tickCumulativeDiff / int56(int32(twapInterval)));

        // Handle rounding for negative ticks
        if (tickCumulativeDiff < 0 && (tickCumulativeDiff % int56(int32(twapInterval)) != 0)) {
            twapTick--;
        }

        // Convert ticks to prices (using 2^96 fixed-point as base)
        spotPrice = _tickToPrice(currentTick);
        twapPrice = _tickToPrice(twapTick);
    }

    /// @dev Convert a tick to a price (simplified — returns sqrtPriceX96 squared / 2^192 * 1e18)
    function _tickToPrice(int24 tick) internal pure returns (uint256) {
        // Use the tick to calculate price
        // price = 1.0001^tick
        // We use the TickMath approach but simplified
        uint256 absTick = tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick));

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // Convert to a price with 1e18 precision
        // ratio is in Q128.128 format, convert to 1e18
        return (ratio * 1e18) >> 128;
    }

    /// @dev Check that cooldown has elapsed
    function _checkCooldown(address token, ActionType actionType) internal view {
        uint256 lastAction = lastActionTime[token][actionType];
        if (lastAction == 0) return; // First action, no cooldown

        uint256 cooldownEnd = lastAction + COOLDOWN_PERIOD;
        if (block.timestamp < cooldownEnd) {
            revert CooldownNotElapsed(token, actionType, cooldownEnd - block.timestamp);
        }
    }

    /// @dev Check and update daily caps and gas limits
    /// @param gasEstimate Estimated gas for this operation (passed by caller)
    function _checkAndUpdateDailyCaps(
        address token,
        ActionType actionType,
        uint256 amount,
        uint256 gasEstimate
    ) internal {
        ActionConfig storage config = actionConfigs[token][actionType];
        if (!config.enabled) return; // No config means no cap

        DailyUsage storage usage = dailyUsage[token][actionType];

        // Reset daily counters if new day
        if (block.timestamp >= usage.resetTimestamp + 1 days) {
            usage.amountUsed = 0;
            usage.gasUsed = 0;
            usage.resetTimestamp = block.timestamp;
        }

        // Check daily cap
        if (config.dailyCap > 0) {
            uint256 remaining = config.dailyCap > usage.amountUsed
                ? config.dailyCap - usage.amountUsed
                : 0;
            if (amount > remaining) {
                revert DailyCapExceeded(token, actionType, amount, remaining);
            }
            usage.amountUsed += amount;
        }

        // Check daily gas
        if (config.dailyUGas > 0 && gasEstimate > 0) {
            uint256 remainingGas = config.dailyUGas > usage.gasUsed
                ? config.dailyUGas - usage.gasUsed
                : 0;
            if (gasEstimate > remainingGas) {
                revert DailyGasExceeded(token, actionType, gasEstimate, remainingGas);
            }
            usage.gasUsed += gasEstimate;
        }
    }

    /// @dev Apply slippage check
    function _checkSlippage(uint256 expected, uint256 actual) internal pure {
        uint256 minAcceptable = (expected * (BPS_DENOMINATOR - SLIPPAGE_BPS)) / BPS_DENOMINATOR;
        if (actual < minAcceptable) {
            revert SlippageExceeded(expected, actual);
        }
    }

    // ─── Receive ETH ─────────────────────────────────────────────────────
    receive() external payable {}
}

/// @dev Minimal Uniswap V3 Pool interface for TWAP
interface IUniswapV3Pool {
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
        );

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX96s);
}
